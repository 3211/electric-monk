# Onboarding Flow

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

1. User signs up → `onboarding_complete` = false
2. AI-generated welcome message displayed
3. User picks username + faction (one-time permanent choice via `choose_sect`)
4. `onboarding_complete` set to true **immediately** after identity step (prevents dropout loop)
5. If user continues: AI-generated faction intro + prayer prompt shown
6. First prayer submitted with `is_onboarding=true` — rejected prayers during onboarding do NOT ban