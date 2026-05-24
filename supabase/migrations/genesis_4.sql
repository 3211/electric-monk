-- ======================================================================================
-- GENESIS 4: VIRTUAL FILE SYSTEM — ENCRYPTION, DELETION, DIRECTORIES & AKASHIC FILES
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is GENESIS_4. It overhauls virtual_files to support:
--   - encryption_level (0-3): 0 = plaintext/decrypted, 1-3 = encrypted tiers
--   - deletion_level (0-2): 0 = visible, 1 = hidden (soft-delete), 2 = purged (flag only)
--     Files are NEVER actually deleted from the database — only flagged.
--   - is_directory: boolean flag for folder placeholder entries
--   - file_size_bytes: exact byte count calculated from file_content text length
--   - parent_path: normalized directory path for tree traversal
--   - content_hash: shortened unique hash for akashic record filenames
--   - Positive & negative address file generation per akashic block scan
--   - Storage pre-calculation for HDD capacity checks
--   - Sect-level akashic record mirroring at sect-name/akashic/.../filename.record
--
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. VIRTUAL FILES — Add new columns
-- ==========================================

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS encryption_level INT NOT NULL DEFAULT 0
  CHECK (encryption_level >= 0 AND encryption_level <= 3);

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS deletion_level INT NOT NULL DEFAULT 0
  CHECK (deletion_level >= 0 AND deletion_level <= 2);

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS is_directory BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS file_size_bytes INT NOT NULL DEFAULT 0;

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS content_hash VARCHAR(64);

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS parent_path VARCHAR;

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS akashic_block_id BIGINT;

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS akashic_address_type VARCHAR(10)
  CHECK (akashic_address_type IS NULL OR akashic_address_type IN ('positive', 'negative'));

ALTER TABLE public.virtual_files
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

COMMENT ON COLUMN public.virtual_files.encryption_level IS 'Encryption tier: 0 = plaintext/decrypted, 1 = light encryption, 2 = medium, 3 = heavy. Akashic records are always 0.';
COMMENT ON COLUMN public.virtual_files.deletion_level IS 'Deletion state: 0 = visible/active, 1 = hidden (soft-delete via /delete), 2 = purged (flag only, file never actually removed from DB).';
COMMENT ON COLUMN public.virtual_files.is_directory IS 'True for folder placeholder entries. Empty directories require a placeholder "folder" file.';
COMMENT ON COLUMN public.virtual_files.file_size_bytes IS 'Exact byte count of file_content (text length). Used for HDD capacity pre-calculation.';
COMMENT ON COLUMN public.virtual_files.content_hash IS 'Shortened unique hash of the akashic address, used as the filename to prevent key collisions.';
COMMENT ON COLUMN public.virtual_files.parent_path IS 'Normalized parent directory path. Used for ASCII tree rendering and path traversal. NULL = root level.';
COMMENT ON COLUMN public.virtual_files.akashic_block_id IS 'The akashic_sectors.block_id that generated this file. NULL for non-akashic files.';
COMMENT ON COLUMN public.virtual_files.akashic_address_type IS 'Whether this is the positive address file or the negative (inverse) address file from an akashic scan.';

-- ==========================================
-- 2. Backfill existing rows
-- ==========================================

-- Calculate file_size_bytes from existing file_content
UPDATE public.virtual_files
SET file_size_bytes = COALESCE(LENGTH(file_content), 0)
WHERE file_size_bytes = 0;

-- Set parent_path from file_path (strip trailing filename)
UPDATE public.virtual_files
SET parent_path = CASE
  WHEN file_path LIKE '%/%' THEN SUBSTRING(file_path FROM 1 FOR LENGTH(file_path) - POSITION('/' IN REVERSE(file_path)))
  ELSE NULL
END
WHERE parent_path IS NULL AND file_path IS NOT NULL;

-- ==========================================
-- 3. HELPER: calculate_total_storage_used
-- ==========================================
-- Sums all visible (deletion_level = 0) file sizes for a machine.
-- Used by the scanner to pre-calculate how many blocks will fit.

CREATE OR REPLACE FUNCTION public.calculate_total_storage_used(
    p_machine_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_total BIGINT;
BEGIN
    SELECT COALESCE(SUM(file_size_bytes), 0) INTO v_total
    FROM public.virtual_files
    WHERE machine_id = p_machine_id
      AND deletion_level = 0
      AND is_directory = false;

    RETURN v_total;
END;
$$;

COMMENT ON FUNCTION public.calculate_total_storage_used(UUID) IS 'Returns total bytes used by all visible (non-deleted) files on a machine. Excludes directory placeholders.';

-- ==========================================
-- 4. HELPER: get_machine_storage_capacity
-- ==========================================
-- Returns the total storage capacity in bytes for a machine.
-- Virtual machines store hardware as flat catalog IDs (storage_id on virtual_machines).

CREATE OR REPLACE FUNCTION public.get_machine_storage_capacity(
    p_machine_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_capacity_mb INT;
BEGIN
    SELECT COALESCE(cs.capacity_mb, 500) INTO v_capacity_mb
    FROM public.virtual_machines vm
    LEFT JOIN public.catalog_storage cs ON vm.storage_id = cs.id
    WHERE vm.machine_id = p_machine_id;

    -- Convert MB to bytes
    RETURN v_capacity_mb::BIGINT * 1024 * 1024;
END;
$$;

COMMENT ON FUNCTION public.get_machine_storage_capacity(UUID) IS 'Returns total storage capacity in bytes for a virtual machine. Reads storage_id directly from virtual_machines.';

-- ==========================================
-- 5. HELPER: calculate_blocks_that_fit
-- ==========================================
-- Given a machine_id and bytes_per_block, returns how many more blocks
-- will fit before storage is full.
-- Each akashic book page is exactly 3200 characters = 3200 bytes (ASCII).
-- Two files per block (positive + negative) = 6400 bytes per block.

CREATE OR REPLACE FUNCTION public.calculate_blocks_that_fit(
    p_machine_id UUID,
    p_bytes_per_block INT DEFAULT 6400
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_capacity_bytes BIGINT;
    v_used_bytes BIGINT;
    v_available_bytes BIGINT;
    v_blocks_that_fit INT;
BEGIN
    v_capacity_bytes := public.get_machine_storage_capacity(p_machine_id);
    v_used_bytes := public.calculate_total_storage_used(p_machine_id);
    v_available_bytes := GREATEST(0, v_capacity_bytes - v_used_bytes);

    v_blocks_that_fit := FLOOR(v_available_bytes / p_bytes_per_block)::INT;

    RETURN v_blocks_that_fit;
END;
$$;

COMMENT ON FUNCTION public.calculate_blocks_that_fit(UUID, INT) IS 'Pre-calculates how many akashic blocks (2 files each, positive + negative) will fit on remaining storage. Default: 6400 bytes per block.';

-- ==========================================
-- 6. HELPER: generate_akashic_filename
-- ==========================================
-- Creates a unique shortened hash filename from an akashic address.
-- Format: ak_{hex_hash}.record
-- Uses first 12 chars of SHA-256-like hash to prevent collisions.

CREATE OR REPLACE FUNCTION public.generate_akashic_filename(
    p_address BIGINT,
    p_address_type VARCHAR  -- 'positive' or 'negative'
)
RETURNS VARCHAR
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_hash_str VARCHAR;
    v_salt VARCHAR;
BEGIN
    -- Create a unique hash from address + type
    v_salt := CASE WHEN p_address_type = 'negative' THEN 'NEG' ELSE 'POS' END;
    v_hash_str := MD5(v_salt || p_address::TEXT);

    RETURN 'ak_' || LEFT(v_hash_str, 12) || '.record';
END;
$$;

COMMENT ON FUNCTION public.generate_akashic_filename(BIGINT, VARCHAR) IS 'Generates a unique shortened-hash filename for akashic record files. Format: ak_{12-char-md5}.record. Prevents key collisions.';

-- ==========================================
-- 7. HELPER: get_file_tree
-- ==========================================
-- Returns the full file tree for a machine, respecting deletion_level.
-- Used by /files command for ASCII tree rendering.

CREATE OR REPLACE FUNCTION public.get_file_tree(
    p_machine_id UUID,
    p_show_hidden BOOLEAN DEFAULT false
)
RETURNS TABLE (
    file_id UUID,
    file_path VARCHAR,
    file_name VARCHAR,
    is_directory BOOLEAN,
    file_size_bytes INT,
    encryption_level INT,
    deletion_level INT,
    akashic_block_id BIGINT,
    akashic_address_type VARCHAR,
    parent_path VARCHAR,
    depth INT,
    sort_path VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE file_tree AS (
        -- Base case: root-level files (no parent_path)
        SELECT
            vf.file_id,
            vf.file_path,
            vf.file_name,
            vf.is_directory,
            vf.file_size_bytes,
            vf.encryption_level,
            vf.deletion_level,
            vf.akashic_block_id,
            vf.akashic_address_type,
            vf.parent_path,
            0 AS depth,
            vf.file_name AS sort_path
        FROM public.virtual_files vf
        WHERE vf.machine_id = p_machine_id
          AND vf.parent_path IS NULL
          AND (p_show_hidden OR vf.deletion_level = 0)

        UNION ALL

        -- Recursive case: children of directories
        SELECT
            child.file_id,
            child.file_path,
            child.file_name,
            child.is_directory,
            child.file_size_bytes,
            child.encryption_level,
            child.deletion_level,
            child.akashic_block_id,
            child.akashic_address_type,
            child.parent_path,
            parent.depth + 1,
            parent.sort_path || '/' || child.file_name
        FROM public.virtual_files child
        JOIN file_tree parent ON child.parent_path = parent.file_path
        WHERE child.machine_id = p_machine_id
          AND (p_show_hidden OR child.deletion_level = 0)
    )
    SELECT * FROM file_tree
    ORDER BY sort_path;
END;
$$;

COMMENT ON FUNCTION public.get_file_tree(UUID, BOOLEAN) IS 'Recursive file tree for ASCII rendering. Respects deletion_level filtering.';

-- ==========================================
-- 8. HELPER: normalize_path
-- ==========================================
-- Normalizes a path string for consistent storage.
-- Removes trailing slashes, resolves '..' and '.'.

CREATE OR REPLACE FUNCTION public.normalize_path(
    p_path VARCHAR
)
RETURNS VARCHAR
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_normalized VARCHAR;
BEGIN
    -- Remove multiple consecutive slashes
    v_normalized := REGEXP_REPLACE(p_path, '/{2,}', '/', 'g');
    -- Remove trailing slash (unless root)
    IF v_normalized <> '/' AND v_normalized LIKE '%/' THEN
        v_normalized := LEFT(v_normalized, LENGTH(v_normalized) - 1);
    END IF;
    -- Remove leading slash for consistency
    IF v_normalized LIKE '/%' THEN
        v_normalized := SUBSTRING(v_normalized FROM 2);
    END IF;
    -- Empty string = root
    IF v_normalized = '' THEN
        RETURN NULL;
    END IF;
    RETURN v_normalized;
END;
$$;

COMMENT ON FUNCTION public.normalize_path(VARCHAR) IS 'Normalizes a file path: removes double slashes, trailing slashes, leading slashes. Empty = root (NULL).';

-- ==========================================
-- 9. HELPER: create_akashic_files_for_block
-- ==========================================
-- Creates both positive and negative address files for an akashic block.
-- Called by the akashic-mining edge function on successful pulse.
-- Also creates the sect mirror copy at sect-name/akashic/.../filename.record

CREATE OR REPLACE FUNCTION public.create_akashic_files_for_block(
    p_machine_id UUID,
    p_block_id BIGINT,
    p_positive_address BIGINT,
    p_negative_address BIGINT,
    p_positive_text TEXT,
    p_negative_text TEXT,
    p_owner_ip inet,
    p_sect_ip inet DEFAULT NULL,
    p_sect_name VARCHAR DEFAULT NULL,
    p_base_path VARCHAR DEFAULT 'akashic_records'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_positive_filename VARCHAR;
    v_negative_filename VARCHAR;
    v_positive_file_id UUID;
    v_negative_file_id UUID;
    v_sect_file_id UUID;
    v_positive_bytes INT;
    v_negative_bytes INT;
    v_db_folder VARCHAR;
BEGIN
    -- Generate unique filenames
    v_positive_filename := public.generate_akashic_filename(p_positive_address, 'positive');
    v_negative_filename := public.generate_akashic_filename(p_negative_address, 'negative');

    -- Calculate exact byte sizes
    v_positive_bytes := LENGTH(p_positive_text);
    v_negative_bytes := LENGTH(p_negative_text);

    -- Generate a deterministic db folder structure from the block_id
    -- Format: akashic_records/B{first_2}/B{next_2}/B{next_2}/
    v_db_folder := p_base_path || '/' ||
                   'B' || LEFT(p_block_id::TEXT, 2) || '/' ||
                   'B' || SUBSTRING(p_block_id::TEXT FROM 3 FOR 2) || '/' ||
                   'B' || SUBSTRING(p_block_id::TEXT FROM 5 FOR 2);

    -- ── Positive address file ──
    INSERT INTO public.virtual_files (
        machine_id,
        owner_identity,
        file_path,
        file_name,
        file_size_mb,
        file_size_bytes,
        file_content,
        encryption_level,
        deletion_level,
        is_directory,
        content_hash,
        parent_path,
        akashic_block_id,
        akashic_address_type
    ) VALUES (
        p_machine_id,
        p_owner_ip,
        v_db_folder,
        v_positive_filename,
        CEIL(v_positive_bytes / (1024.0 * 1024.0))::INT,
        v_positive_bytes,
        p_positive_text,
        0,  -- Akashic records are decrypted
        0,  -- Visible
        false,
        MD5(p_positive_address::TEXT),
        v_db_folder,
        p_block_id,
        'positive'
    )
    RETURNING file_id INTO v_positive_file_id;

    -- ── Negative address file ──
    INSERT INTO public.virtual_files (
        machine_id,
        owner_identity,
        file_path,
        file_name,
        file_size_mb,
        file_size_bytes,
        file_content,
        encryption_level,
        deletion_level,
        is_directory,
        content_hash,
        parent_path,
        akashic_block_id,
        akashic_address_type
    ) VALUES (
        p_machine_id,
        p_owner_ip,
        v_db_folder,
        v_negative_filename,
        CEIL(v_negative_bytes / (1024.0 * 1024.0))::INT,
        v_negative_bytes,
        p_negative_text,
        0,  -- Akashic records are decrypted
        0,  -- Visible
        false,
        MD5(p_negative_address::TEXT),
        v_db_folder,
        p_block_id,
        'negative'
    )
    RETURNING file_id INTO v_negative_file_id;

    -- ── Sect mirror copy (if player has a faction) ──
    -- Stored at: sect-name/akashic/B{xx}/B{xx}/B{xx}/filename.record
    IF p_sect_ip IS NOT NULL AND p_sect_name IS NOT NULL THEN
        -- Find sect's VM that has this IP or create entry on the same machine
        -- with a sect-specific path prefix
        DECLARE
            v_sect_path VARCHAR;
        BEGIN
            v_sect_path := p_sect_name || '/akashic/' ||
                          'B' || LEFT(p_block_id::TEXT, 2) || '/' ||
                          'B' || SUBSTRING(p_block_id::TEXT FROM 3 FOR 2) || '/' ||
                          'B' || SUBSTRING(p_block_id::TEXT FROM 5 FOR 2);

            INSERT INTO public.virtual_files (
                machine_id,
                owner_identity,
                file_path,
                file_name,
                file_size_mb,
                file_size_bytes,
                file_content,
                encryption_level,
                deletion_level,
                is_directory,
                content_hash,
                parent_path,
                akashic_block_id,
                akashic_address_type
            ) VALUES (
                p_machine_id,
                p_sect_ip,
                v_sect_path,
                v_positive_filename,
                CEIL(v_positive_bytes / (1024.0 * 1024.0))::INT,
                v_positive_bytes,
                p_positive_text,
                0,
                0,
                false,
                MD5(p_positive_address::TEXT),
                v_sect_path,
                p_block_id,
                'positive'
            )
            RETURNING file_id INTO v_sect_file_id;
        END;
    END IF;

    RETURN json_build_object(
        'success', true,
        'block_id', p_block_id,
        'positive_file_id', v_positive_file_id,
        'negative_file_id', v_negative_file_id,
        'positive_filename', v_positive_filename,
        'negative_filename', v_negative_filename,
        'positive_bytes', v_positive_bytes,
        'negative_bytes', v_negative_bytes,
        'db_folder', v_db_folder,
        'sect_file_id', v_sect_file_id,
        'total_bytes_written', v_positive_bytes + v_negative_bytes
    );
END;
$$;

COMMENT ON FUNCTION public.create_akashic_files_for_block(UUID, BIGINT, BIGINT, BIGINT, TEXT, TEXT, inet, inet, VARCHAR, VARCHAR) IS 'Creates positive + negative akashic record files for a scanned block, plus a sect mirror copy. Files have encryption_level=0 (decrypted). Uses deterministic folder structure from block_id.';

-- ==========================================
-- 10. HELPER: soft_delete_file
-- ==========================================
-- Implements the /delete command. Never actually removes rows.
-- Sets deletion_level = 1 (hidden) or 2 (purged flag).

CREATE OR REPLACE FUNCTION public.soft_delete_file(
    p_file_id UUID,
    p_deletion_level INT DEFAULT 1
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_file RECORD;
BEGIN
    SELECT * INTO v_file
    FROM public.virtual_files
    WHERE file_id = p_file_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'File not found');
    END IF;

    -- If it's a directory, cascade soft-delete children
    IF v_file.is_directory THEN
        UPDATE public.virtual_files
        SET deletion_level = p_deletion_level,
            updated_at = now()
        WHERE (file_path LIKE v_file.file_path || '/%' OR file_path = v_file.file_path)
          AND machine_id = v_file.machine_id;
    END IF;

    UPDATE public.virtual_files
    SET deletion_level = p_deletion_level,
        updated_at = now()
    WHERE file_id = p_file_id;

    RETURN json_build_object(
        'success', true,
        'file_id', p_file_id,
        'file_name', v_file.file_name,
        'deletion_level', p_deletion_level,
        'was_directory', v_file.is_directory
    );
END;
$$;

COMMENT ON FUNCTION public.soft_delete_file(UUID, INT) IS 'Soft-deletes a file by setting deletion_level (1=hidden, 2=purged). Files are NEVER actually removed from the database. Cascades to children if directory.';

-- ==========================================
-- 11. HELPER: encrypt_file
-- ==========================================
-- Sets the encryption_level on a file. 0 = decrypted, 3 = max.

CREATE OR REPLACE FUNCTION public.encrypt_file(
    p_file_id UUID,
    p_encryption_level INT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_file RECORD;
BEGIN
    SELECT * INTO v_file
    FROM public.virtual_files
    WHERE file_id = p_file_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'File not found');
    END IF;

    UPDATE public.virtual_files
    SET encryption_level = p_encryption_level,
        updated_at = now()
    WHERE file_id = p_file_id;

    RETURN json_build_object(
        'success', true,
        'file_id', p_file_id,
        'file_name', v_file.file_name,
        'encryption_level', p_encryption_level
    );
END;
$$;

COMMENT ON FUNCTION public.encrypt_file(UUID, INT) IS 'Sets encryption level on a file (0-3). 0 = decrypted/plaintext, 3 = maximum encryption.';

-- ==========================================
-- 12. INDEXES
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_vfiles_deletion ON public.virtual_files(deletion_level) WHERE deletion_level = 0;
CREATE INDEX IF NOT EXISTS idx_vfiles_encryption ON public.virtual_files(encryption_level);
CREATE INDEX IF NOT EXISTS idx_vfiles_parent_path ON public.virtual_files(parent_path);
CREATE INDEX IF NOT EXISTS idx_vfiles_is_directory ON public.virtual_files(is_directory);
CREATE INDEX IF NOT EXISTS idx_vfiles_akashic_block ON public.virtual_files(akashic_block_id) WHERE akashic_block_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_vfiles_machine_deletion ON public.virtual_files(machine_id, deletion_level);
CREATE INDEX IF NOT EXISTS idx_vfiles_content_hash ON public.virtual_files(content_hash) WHERE content_hash IS NOT NULL;

-- ==========================================
-- 13. TRIGGER: auto-update updated_at
-- ==========================================

CREATE OR REPLACE FUNCTION public.update_vfile_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vfiles_updated_at ON public.virtual_files;
CREATE TRIGGER trg_vfiles_updated_at
    BEFORE UPDATE ON public.virtual_files
    FOR EACH ROW
    EXECUTE FUNCTION public.update_vfile_timestamp();

-- ==========================================
-- 14. TRIGGER: auto-calculate file_size_bytes
-- ==========================================

CREATE OR REPLACE FUNCTION public.calculate_vfile_size()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.file_content IS NOT NULL AND NOT NEW.is_directory THEN
        NEW.file_size_bytes := LENGTH(NEW.file_content);
        NEW.file_size_mb := CEIL(NEW.file_size_bytes / (1024.0 * 1024.0))::INT;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vfiles_calc_size ON public.virtual_files;
CREATE TRIGGER trg_vfiles_calc_size
    BEFORE INSERT OR UPDATE OF file_content ON public.virtual_files
    FOR EACH ROW
    EXECUTE FUNCTION public.calculate_vfile_size();

-- ==========================================
-- 15. GRANTS
-- ==========================================

GRANT EXECUTE ON FUNCTION public.calculate_total_storage_used(UUID) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_machine_storage_capacity(UUID) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_blocks_that_fit(UUID, INT) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_akashic_filename(BIGINT, VARCHAR) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_file_tree(UUID, BOOLEAN) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_path(VARCHAR) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.create_akashic_files_for_block(UUID, BIGINT, BIGINT, BIGINT, TEXT, TEXT, inet, inet, VARCHAR, VARCHAR) TO service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_file(UUID, INT) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.encrypt_file(UUID, INT) TO service_role, authenticated;

COMMIT;