-- =====================================================================
-- LifeHelm — Schéma SQL PostgreSQL (V1)
-- "Take the helm of your life"
-- =====================================================================
-- Ce script crée toutes les tables directement en SQL,
-- indépendamment de Prisma (au cas où Prisma ne serait pas dispo).
-- =====================================================================

-- =====================================================================
-- ENUMS
-- =====================================================================
CREATE TYPE "Plan" AS ENUM ('FREE', 'PRO', 'FAMILY');
CREATE TYPE "AccountType" AS ENUM ('CASH', 'MOBILE_MONEY_MTN', 'MOBILE_MONEY_MOOV', 'MOBILE_MONEY_WAVE', 'BANK', 'SAVINGS', 'TONTINE', 'OTHER');
CREATE TYPE "TransactionType" AS ENUM ('INCOME', 'EXPENSE', 'TRANSFER');
CREATE TYPE "BudgetMethod" AS ENUM ('FIFTY_THIRTY_TWENTY', 'ENVELOPES', 'CUSTOM');
CREATE TYPE "DebtStrategy" AS ENUM ('SNOWBALL', 'AVALANCHE');
CREATE TYPE "DebtDirection" AS ENUM ('OWED', 'OWING');
CREATE TYPE "BillStatus" AS ENUM ('PENDING', 'PAID', 'LATE');
CREATE TYPE "LifeDomain" AS ENUM ('FINANCE', 'HEALTH', 'CAREER', 'RELATIONS', 'PERSONAL', 'SPIRITUAL', 'FAMILY');
CREATE TYPE "GoalType" AS ENUM ('BINARY', 'NUMERIC', 'MILESTONE');
CREATE TYPE "GoalStatus" AS ENUM ('ACTIVE', 'PAUSED', 'COMPLETED', 'ABANDONED');
CREATE TYPE "GoalPriority" AS ENUM ('LOW', 'MEDIUM', 'HIGH');
CREATE TYPE "TaskStatus" AS ENUM ('TODO', 'IN_PROGRESS', 'DONE', 'BLOCKED');
CREATE TYPE "HabitFrequency" AS ENUM ('DAILY', 'WEEKLY', 'CUSTOM');
CREATE TYPE "HabitType" AS ENUM ('BINARY', 'NUMERIC');
CREATE TYPE "Mood" AS ENUM ('VERY_BAD', 'BAD', 'NEUTRAL', 'GOOD', 'VERY_GOOD');
CREATE TYPE "ContactCircle" AS ENUM ('FAMILY_CLOSE', 'FAMILY_EXTENDED', 'FRIEND', 'COLLEAGUE', 'MENTOR', 'NETWORK');
CREATE TYPE "AiRole" AS ENUM ('USER', 'ASSISTANT', 'SYSTEM');
CREATE TYPE "InsightType" AS ENUM ('WEEKLY', 'MONTHLY', 'ALERT', 'CORRELATION');
CREATE TYPE "InsightSeverity" AS ENUM ('INFO', 'WARNING', 'POSITIVE', 'CRITICAL');
CREATE TYPE "AppLanguage" AS ENUM ('FR', 'FON', 'BARIBA', 'YORUBA');
CREATE TYPE "AppMode" AS ENUM ('STANDARD', 'ACCESSIBLE');

-- =====================================================================
-- USERS & AUTH
-- =====================================================================
CREATE TABLE "users" (
    "id" TEXT PRIMARY KEY,
    "email" TEXT UNIQUE NOT NULL,
    "password_hash" TEXT NOT NULL,
    "first_name" TEXT NOT NULL,
    "last_name" TEXT,
    "phone" TEXT,
    "avatar_url" TEXT,
    "plan" "Plan" NOT NULL DEFAULT 'FREE',
    "language" "AppLanguage" NOT NULL DEFAULT 'FR',
    "app_mode" "AppMode" NOT NULL DEFAULT 'STANDARD',
    "currency" TEXT NOT NULL DEFAULT 'XOF',
    "onboarded" BOOLEAN NOT NULL DEFAULT false,
    "accessible_onboarded" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "last_login_at" TIMESTAMP(3)
);

CREATE TABLE "sessions" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "user_agent" TEXT,
    "ip" TEXT,
    "device_name" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked" BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "sessions_user_id_idx" ON "sessions"("user_id");

CREATE TABLE "refresh_tokens" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "token" TEXT UNIQUE NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked" BOOLEAN NOT NULL DEFAULT false,
    "replaced_by" TEXT,
    CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

CREATE TABLE "user_settings" (
    "user_id" TEXT PRIMARY KEY,
    "notifications_enabled" BOOLEAN NOT NULL DEFAULT true,
    "daily_reminder_hour" INTEGER NOT NULL DEFAULT 8,
    "weekly_report_day" INTEGER NOT NULL DEFAULT 0,
    "weekly_report_hour" INTEGER NOT NULL DEFAULT 9,
    "sleep_goal_hours" INTEGER NOT NULL DEFAULT 7,
    "hydration_goal_ml" INTEGER NOT NULL DEFAULT 2000,
    "weekly_workout_goal" INTEGER NOT NULL DEFAULT 3,
    "monthly_savings_pct" INTEGER NOT NULL DEFAULT 20,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);

-- =====================================================================
-- FINANCE - ACCOUNTS
-- =====================================================================
CREATE TABLE "accounts" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "AccountType" NOT NULL,
    "balance" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "currency" TEXT NOT NULL DEFAULT 'XOF',
    "color" TEXT,
    "icon" TEXT,
    "archived" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "accounts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "accounts_user_id_idx" ON "accounts"("user_id");

-- =====================================================================
-- FINANCE - TRANSACTIONS
-- =====================================================================
CREATE TABLE "transactions" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "account_id" TEXT NOT NULL,
    "type" "TransactionType" NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "category" TEXT,
    "subcategory" TEXT,
    "label" TEXT NOT NULL,
    "note" TEXT,
    "tags" TEXT[],
    "receipt_url" TEXT,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "recurring" BOOLEAN NOT NULL DEFAULT false,
    "recurring_rule" TEXT,
    "transfer_to_account_id" TEXT,
    "transfer_from_account_id" TEXT,
    "savings_goal_id" TEXT,
    "boutique_log_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "transactions_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "accounts"("id") ON DELETE CASCADE,
    CONSTRAINT "transactions_transfer_to_account_id_fkey" FOREIGN KEY ("transfer_to_account_id") REFERENCES "accounts"("id"),
    CONSTRAINT "transactions_transfer_from_account_id_fkey" FOREIGN KEY ("transfer_from_account_id") REFERENCES "accounts"("id")
    -- FK vers savings_goals ajoutée plus bas (après création de savings_goals)
);
CREATE INDEX "transactions_user_id_idx" ON "transactions"("user_id");
CREATE INDEX "transactions_account_id_idx" ON "transactions"("account_id");
CREATE INDEX "transactions_date_idx" ON "transactions"("date");
CREATE INDEX "transactions_category_idx" ON "transactions"("category");

-- =====================================================================
-- FINANCE - BUDGETS
-- =====================================================================
CREATE TABLE "budgets" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "month" TIMESTAMP(3) NOT NULL,
    "method" "BudgetMethod" NOT NULL DEFAULT 'FIFTY_THIRTY_TWENTY',
    "total_income" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "needs_pct" INTEGER NOT NULL DEFAULT 50,
    "wants_pct" INTEGER NOT NULL DEFAULT 30,
    "savings_pct" INTEGER NOT NULL DEFAULT 20,
    "rollover" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "budgets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "budgets_user_id_month_key" UNIQUE ("user_id", "month")
);

CREATE TABLE "budget_categories" (
    "id" TEXT PRIMARY KEY,
    "budget_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "allocated" DECIMAL(14,2) NOT NULL,
    "spent" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "rollover_from" DECIMAL(14,2),
    CONSTRAINT "budget_categories_budget_id_fkey" FOREIGN KEY ("budget_id") REFERENCES "budgets"("id") ON DELETE CASCADE
);
CREATE INDEX "budget_categories_budget_id_idx" ON "budget_categories"("budget_id");

-- =====================================================================
-- FINANCE - SAVINGS GOALS
-- =====================================================================
CREATE TABLE "savings_goals" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "target_amount" DECIMAL(14,2) NOT NULL,
    "current_amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "deadline" TIMESTAMP(3),
    "image_url" TEXT,
    "archived" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "savings_goals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "savings_goals_user_id_idx" ON "savings_goals"("user_id");

-- Ajout de la FK différée entre transactions et savings_goals
ALTER TABLE "transactions"
  ADD CONSTRAINT "transactions_savings_goal_id_fkey"
  FOREIGN KEY ("savings_goal_id") REFERENCES "savings_goals"("id");

-- =====================================================================
-- FINANCE - TONTINES
-- =====================================================================
CREATE TABLE "tontines" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "contribution_amount" DECIMAL(14,2) NOT NULL,
    "frequency" TEXT NOT NULL DEFAULT 'MONTHLY',
    "start_date" TIMESTAMP(3) NOT NULL,
    "end_date" TIMESTAMP(3),
    "my_rank" INTEGER NOT NULL,
    "total_members" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "tontines_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "tontines_user_id_idx" ON "tontines"("user_id");

CREATE TABLE "tontine_members" (
    "id" TEXT PRIMARY KEY,
    "tontine_id" TEXT NOT NULL,
    "user_id" TEXT,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "rank" INTEGER NOT NULL,
    "paid" BOOLEAN NOT NULL DEFAULT false,
    "paid_at" TIMESTAMP(3),
    "received" BOOLEAN NOT NULL DEFAULT false,
    "received_at" TIMESTAMP(3),
    CONSTRAINT "tontine_members_tontine_id_fkey" FOREIGN KEY ("tontine_id") REFERENCES "tontines"("id") ON DELETE CASCADE,
    CONSTRAINT "tontine_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id")
);
CREATE INDEX "tontine_members_tontine_id_idx" ON "tontine_members"("tontine_id");

-- =====================================================================
-- FINANCE - DEBTS
-- =====================================================================
CREATE TABLE "debts" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "direction" "DebtDirection" NOT NULL,
    "person_name" TEXT NOT NULL,
    "person_phone" TEXT,
    "amount" DECIMAL(14,2) NOT NULL,
    "interest_rate" DECIMAL(5,2),
    "due_date" TIMESTAMP(3),
    "note" TEXT,
    "settled" BOOLEAN NOT NULL DEFAULT false,
    "settled_at" TIMESTAMP(3),
    "strategy" "DebtStrategy" DEFAULT 'SNOWBALL',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "debts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "debts_user_id_idx" ON "debts"("user_id");

CREATE TABLE "debt_payments" (
    "id" TEXT PRIMARY KEY,
    "debt_id" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "note" TEXT,
    CONSTRAINT "debt_payments_debt_id_fkey" FOREIGN KEY ("debt_id") REFERENCES "debts"("id") ON DELETE CASCADE
);
CREATE INDEX "debt_payments_debt_id_idx" ON "debt_payments"("debt_id");

-- =====================================================================
-- FINANCE - BILLS
-- =====================================================================
CREATE TABLE "bills" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "category" TEXT,
    "recurrence" TEXT NOT NULL DEFAULT 'MONTHLY',
    "due_day" INTEGER NOT NULL,
    "next_due_date" TIMESTAMP(3) NOT NULL,
    "reminder_days" INTEGER NOT NULL DEFAULT 3,
    "status" "BillStatus" NOT NULL DEFAULT 'PENDING',
    "paid_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "bills_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "bills_user_id_idx" ON "bills"("user_id");

CREATE TABLE "bill_history" (
    "id" TEXT PRIMARY KEY,
    "bill_id" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "paid_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "bill_history_bill_id_fkey" FOREIGN KEY ("bill_id") REFERENCES "bills"("id") ON DELETE CASCADE
);
CREATE INDEX "bill_history_bill_id_idx" ON "bill_history"("bill_id");

-- =====================================================================
-- OBJECTIFS - LIFE GOALS
-- =====================================================================
CREATE TABLE "life_goals" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "domain" "LifeDomain" NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "type" "GoalType" NOT NULL DEFAULT 'BINARY',
    "priority" "GoalPriority" NOT NULL DEFAULT 'MEDIUM',
    "status" "GoalStatus" NOT NULL DEFAULT 'ACTIVE',
    "target_value" DECIMAL(14,2),
    "current_value" DECIMAL(14,2),
    "unit" TEXT,
    "start_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deadline" TIMESTAMP(3),
    "is_public" BOOLEAN NOT NULL DEFAULT false,
    "image_url" TEXT,
    "vision" TEXT,
    "vision_horizon" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "life_goals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "life_goals_user_id_idx" ON "life_goals"("user_id");

CREATE TABLE "goal_projects" (
    "id" TEXT PRIMARY KEY,
    "goal_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "start_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "end_date" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "goal_projects_goal_id_fkey" FOREIGN KEY ("goal_id") REFERENCES "life_goals"("id") ON DELETE CASCADE
);
CREATE INDEX "goal_projects_goal_id_idx" ON "goal_projects"("goal_id");

CREATE TABLE "goal_tasks" (
    "id" TEXT PRIMARY KEY,
    "project_id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "status" "TaskStatus" NOT NULL DEFAULT 'TODO',
    "order" INTEGER NOT NULL DEFAULT 0,
    "due_date" TIMESTAMP(3),
    "completed_at" TIMESTAMP(3),
    "blocked_by" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "goal_tasks_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "goal_projects"("id") ON DELETE CASCADE
);
CREATE INDEX "goal_tasks_project_id_idx" ON "goal_tasks"("project_id");

CREATE TABLE "goal_journal" (
    "id" TEXT PRIMARY KEY,
    "goal_id" TEXT NOT NULL,
    "note" TEXT NOT NULL,
    "progress" INTEGER,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "goal_journal_goal_id_fkey" FOREIGN KEY ("goal_id") REFERENCES "life_goals"("id") ON DELETE CASCADE
);
CREATE INDEX "goal_journal_goal_id_idx" ON "goal_journal"("goal_id");

-- =====================================================================
-- ROUTINES - HABITS
-- =====================================================================
CREATE TABLE "habits" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "type" "HabitType" NOT NULL DEFAULT 'BINARY',
    "frequency" "HabitFrequency" NOT NULL DEFAULT 'DAILY',
    "target_value" DECIMAL(10,2),
    "unit" TEXT,
    "color" TEXT,
    "icon" TEXT,
    "reminder_hour" INTEGER,
    "reminder_min" INTEGER,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "habits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "habits_user_id_idx" ON "habits"("user_id");

CREATE TABLE "habit_logs" (
    "id" TEXT PRIMARY KEY,
    "habit_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "value" DECIMAL(10,2),
    "completed" BOOLEAN NOT NULL DEFAULT true,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "habit_logs_habit_id_fkey" FOREIGN KEY ("habit_id") REFERENCES "habits"("id") ON DELETE CASCADE,
    CONSTRAINT "habit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "habit_logs_habit_id_date_key" UNIQUE ("habit_id", "date")
);
CREATE INDEX "habit_logs_user_id_idx" ON "habit_logs"("user_id");

CREATE TABLE "morning_rituals" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "steps" JSONB NOT NULL,
    "total_duration" INTEGER NOT NULL DEFAULT 0,
    "completed" BOOLEAN NOT NULL DEFAULT false,
    "completed_at" TIMESTAMP(3),
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "morning_rituals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "morning_rituals_user_id_date_key" UNIQUE ("user_id", "date")
);

CREATE TABLE "evening_reviews" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "gratitude" TEXT[],
    "reflection" TEXT,
    "top_priorities" TEXT[],
    "energy_level" INTEGER,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "evening_reviews_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "evening_reviews_user_id_date_key" UNIQUE ("user_id", "date")
);

-- =====================================================================
-- SANTÉ
-- =====================================================================
CREATE TABLE "sleep_logs" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "bedtime" TIMESTAMP(3) NOT NULL,
    "wake_time" TIMESTAMP(3) NOT NULL,
    "duration_min" INTEGER NOT NULL,
    "quality" INTEGER NOT NULL,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "sleep_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "sleep_logs_user_id_date_key" UNIQUE ("user_id", "date")
);
CREATE INDEX "sleep_logs_user_id_idx" ON "sleep_logs"("user_id");

CREATE TABLE "mood_logs" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "mood" "Mood" NOT NULL,
    "energy" INTEGER NOT NULL,
    "emotions" TEXT[],
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "mood_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "mood_logs_user_id_date_key" UNIQUE ("user_id", "date")
);
CREATE INDEX "mood_logs_user_id_idx" ON "mood_logs"("user_id");

CREATE TABLE "workout_logs" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "type" TEXT NOT NULL,
    "duration_min" INTEGER NOT NULL,
    "intensity" INTEGER NOT NULL,
    "calories" INTEGER,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "workout_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "workout_logs_user_id_idx" ON "workout_logs"("user_id");
CREATE INDEX "workout_logs_date_idx" ON "workout_logs"("date");

CREATE TABLE "hydration_logs" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "amount_ml" INTEGER NOT NULL,
    "goal_ml" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "hydration_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "hydration_logs_user_id_date_key" UNIQUE ("user_id", "date")
);
CREATE INDEX "hydration_logs_user_id_idx" ON "hydration_logs"("user_id");

-- =====================================================================
-- CAREER & CONTACTS
-- =====================================================================
CREATE TABLE "career_profiles" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT UNIQUE NOT NULL,
    "job_title" TEXT,
    "company" TEXT,
    "sector" TEXT,
    "employment_type" TEXT,
    "skills" JSONB,
    "annual_revenue_goal" DECIMAL(14,2),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "career_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);

CREATE TABLE "contacts" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "first_name" TEXT NOT NULL,
    "last_name" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "city" TEXT,
    "circle" "ContactCircle" NOT NULL DEFAULT 'NETWORK',
    "birthday" TIMESTAMP(3),
    "last_contact_at" TIMESTAMP(3),
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "contacts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "contacts_user_id_idx" ON "contacts"("user_id");

-- =====================================================================
-- HELM AI
-- =====================================================================
CREATE TABLE "ai_conversations" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "title" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ai_conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "ai_conversations_user_id_idx" ON "ai_conversations"("user_id");

CREATE TABLE "ai_messages" (
    "id" TEXT PRIMARY KEY,
    "conversation_id" TEXT NOT NULL,
    "role" "AiRole" NOT NULL,
    "content" TEXT NOT NULL,
    "tokens_used" INTEGER,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ai_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "ai_conversations"("id") ON DELETE CASCADE
);
CREATE INDEX "ai_messages_conversation_id_idx" ON "ai_messages"("conversation_id");

CREATE TABLE "ai_insights" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "type" "InsightType" NOT NULL,
    "severity" "InsightSeverity" NOT NULL DEFAULT 'INFO',
    "title" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "metadata" JSONB,
    "read" BOOLEAN NOT NULL DEFAULT false,
    "read_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ai_insights_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "ai_insights_user_id_idx" ON "ai_insights"("user_id");

-- =====================================================================
-- MODE ACCESSIBLE
-- =====================================================================
CREATE TABLE "daily_boutique_logs" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "opening_capital" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "restock_cost" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "total_sales" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "net_profit" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "daily_boutique_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
    CONSTRAINT "daily_boutique_logs_user_id_date_key" UNIQUE ("user_id", "date")
);
CREATE INDEX "daily_boutique_logs_user_id_idx" ON "daily_boutique_logs"("user_id");

CREATE TABLE "client_ardoises" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "client_name" TEXT NOT NULL,
    "client_phone" TEXT,
    "total_debt" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "settled" BOOLEAN NOT NULL DEFAULT false,
    "settled_at" TIMESTAMP(3),
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "client_ardoises_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "client_ardoises_user_id_idx" ON "client_ardoises"("user_id");

CREATE TABLE "ardoise_entries" (
    "id" TEXT PRIMARY KEY,
    "ardoise_id" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "direction" TEXT NOT NULL,
    "note" TEXT,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ardoise_entries_ardoise_id_fkey" FOREIGN KEY ("ardoise_id") REFERENCES "client_ardoises"("id") ON DELETE CASCADE
);
CREATE INDEX "ardoise_entries_ardoise_id_idx" ON "ardoise_entries"("ardoise_id");

CREATE TABLE "supplier_credits" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT NOT NULL,
    "supplier_name" TEXT NOT NULL,
    "supplier_phone" TEXT,
    "amount" DECIMAL(14,2) NOT NULL,
    "due_date" TIMESTAMP(3),
    "settled" BOOLEAN NOT NULL DEFAULT false,
    "settled_at" TIMESTAMP(3),
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "supplier_credits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);
CREATE INDEX "supplier_credits_user_id_idx" ON "supplier_credits"("user_id");
