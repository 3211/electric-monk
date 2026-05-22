import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import postgres from "https://deno.land/x/postgresjs@v3.3.4/mod.js";

const dbUrl = Deno.env.get("SUPABASE_DB_URL");
if (!dbUrl) throw new Error("SUPABASE_DB_URL is required");

const sql = postgres(dbUrl);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const method = req.method;

  try {
    if (method === "GET") {
      const machineId = url.searchParams.get("machine_id");
      const targetPath = url.searchParams.get("target_path");

      if (!machineId || !targetPath) {
        return new Response(JSON.stringify({ error: "Missing parameters" }), { status: 400, headers: corsHeaders });
      }

      const files = await sql`
        SELECT file_id, file_path, file_name, file_size_mb, created_at
        FROM virtual_files
        WHERE machine_id = ${machineId} AND file_path = ${targetPath}
      `;
      
      return new Response(JSON.stringify(files), { status: 200, headers: corsHeaders });
    }

    if (method === "DELETE") {
      const { machine_id, target_path } = await req.json();

      await sql`
        DELETE FROM virtual_files
        WHERE machine_id = ${machine_id}
        AND file_path LIKE ${target_path} || '%'
      `;

      return new Response(JSON.stringify({ success: true }), { status: 200, headers: corsHeaders });
    }

    if (method === "PUT") {
      const { file_id, new_content } = await req.json();

      await sql.begin(async (tx) => {
        await tx`SELECT 1 FROM virtual_files WHERE file_id = ${file_id} FOR UPDATE`;
        await tx`UPDATE virtual_files SET file_content = ${new_content} WHERE file_id = ${file_id}`;
      });

      return new Response(JSON.stringify({ success: true }), { status: 200, headers: corsHeaders });
    }

    if (method === "POST") {
      const { machine_id, source_ip, action_type, details, is_spoofed = false } = await req.json();

      await sql`
        INSERT INTO virtual_logs (machine_id, source_ip, action_type, details, is_spoofed)
        VALUES (${machine_id}, ${source_ip}, ${action_type}, ${details}, ${is_spoofed})
      `;

      return new Response(JSON.stringify({ success: true }), { status: 200, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: corsHeaders });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: corsHeaders });
  }
});