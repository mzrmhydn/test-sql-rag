# Complete Project Documentation

**Project:** NUST DBS Agent — Natural Language SQL Assistant
**Course:** Data Structures / Database Systems (2nd Semester)
**Institution:** NUST, Islamabad
**Last Updated:** April 2026

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Database Schema](#3-database-schema)
4. [Design Rationale](#4-design-rationale)
5. [Key SQL Queries](#5-key-sql-queries)
6. [Setup Guide](#6-setup-guide)
7. [User Guide](#7-user-guide)
8. [API Reference](#8-api-reference)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Project Overview

NUST DBS Agent is a conversational SQL assistant for the NUST university database. Non-technical administrative staff (admissions officers, registrar staff, academic advisors) submit questions in plain English and receive concise, plain-English answers drawn from live MySQL data. No SQL knowledge is required.

**Core capabilities:**
- Natural language to MySQL query translation
- Automatic query self-correction on error
- Semantic few-shot example retrieval (FAISS)
- Transparent reasoning trace (collapsible in UI)
- Scope enforcement (NUST data only)
- Strict read-only access

**What it is not:**
- A general-purpose chatbot (refuses off-topic questions)
- A data-entry interface (SELECT queries only)
- A cloud-connected service (all processing is local)

---

## 2. Architecture

### 2.1 High-Level Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Browser  (React 19 + Vite + Tailwind CSS v4)           │
│  http://localhost:5173                                   │
│                                                         │
│  Chat UI ──── POST /api/ask ──── GET /api/schema        │
└─────────────────────┬───────────────────────────────────┘
                      │ HTTP
┌─────────────────────▼───────────────────────────────────┐
│  FastAPI Backend  (api.py)   http://localhost:8000      │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  build_user_input()                               │  │
│  │   └─ FAISS vector store                          │  │
│  │       (nomic-embed-text embeddings)              │  │
│  │       22 few-shot Q&A examples                   │  │
│  │       threshold: L2 distance < 0.35              │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  LangGraph ReAct Agent                            │  │
│  │   ├─ ChatOllama (llama3.1, temp=0)               │  │
│  │   ├─ sql_db_list_tables                          │  │
│  │   ├─ sql_db_describe_tables                      │  │
│  │   ├─ sql_db_query_checker                        │  │
│  │   └─ sql_db_query                                │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  sanitize_final_answer() ──→ AnswerResponse JSON        │
└─────────────────────┬───────────────────────────────────┘
                      │ SQLAlchemy + PyMySQL
┌─────────────────────▼───────────────────────────────────┐
│  MySQL 8.0  (nust_university database)                  │
│  16 tables · 2 views · 2 triggers · 22 indexes          │
└─────────────────────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│  Ollama  http://localhost:11434                         │
│  Models: llama3.1 (chat) · nomic-embed-text (embed)    │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Request Lifecycle

1. User submits a question in the chat UI.
2. Frontend sends `POST /api/ask` with `{"question": "..."}`.
3. Backend's `build_user_input()` embeds the question and searches FAISS for similar examples.
4. If a match is found (distance < 0.35), the matching SQL is appended to the question as internal guidance.
5. The LangGraph ReAct agent receives the enhanced prompt + system prompt (with full schema injected).
6. Agent reasons in a loop:
   - May call `list_tables` to confirm available tables
   - May call `describe_tables` to inspect column names
   - Generates SQL, calls `query_checker` to validate
   - Executes via `query` tool
   - Formulates answer from results
7. `sanitize_final_answer()` strips any leaked SQL, tables, or preamble text.
8. Backend returns `{"answer": "...", "steps": [...]}`.
9. Frontend renders the answer and a collapsible steps panel.

### 2.3 Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Language Model | Llama 3.1 via Ollama | 7B parameters |
| Embeddings | nomic-embed-text via Ollama | — |
| Agent Framework | LangGraph + LangChain | ≥ 0.3.0 |
| Vector Store | FAISS CPU | ≥ 1.8.0 |
| Backend API | FastAPI + Uvicorn | — |
| ORM | SQLAlchemy + PyMySQL | ≥ 2.0.0 |
| Database | MySQL 8.0 InnoDB | 8.0 |
| Frontend | React 19 + Vite 8 | — |
| CSS | Tailwind CSS v4 | — |
| Package Manager | pip (Python), npm (JS) | — |

---

## 3. Database Schema

### 3.1 Entity Overview

16 tables organised in two pipelines converging at `student`:

**Admissions pipeline:**
`applicant` → `test_attempt` ← `entry_test`
`applicant` → `application` → `offer` → (triggers student creation)

**Academic pipeline:**
`school` → `faculty`, `program`, `course`
`program` ↔ `course` (via `program_course`)
`course` ↔ `course` (via `prerequisite`)
`term`, `classroom`, `faculty` → `section`
`student` → `enrollment` ← `section`

### 3.2 Table Definitions

#### school
| Column | Type | Constraints |
|--------|------|-------------|
| school_id | VARCHAR(10) | PK |
| school_name | VARCHAR(100) | NOT NULL, UNIQUE |
| abbreviation | VARCHAR(10) | NOT NULL, UNIQUE |
| established_year | SMALLINT | NOT NULL |

**Sample data:** SEECS (School of Electrical Engineering & CS, est. 1993), NBS (NUST Business School, est. 1998)

---

#### faculty
| Column | Type | Constraints |
|--------|------|-------------|
| faculty_id | VARCHAR(15) | PK |
| school_id | VARCHAR(10) | FK → school, NOT NULL |
| full_name | VARCHAR(100) | NOT NULL |
| email | VARCHAR(100) | NOT NULL, UNIQUE |
| designation | ENUM | NOT NULL |

Designation values: `Lecturer`, `Assistant Professor`, `Associate Professor`, `Professor`

---

#### program
| Column | Type | Constraints |
|--------|------|-------------|
| program_id | VARCHAR(10) | PK |
| school_id | VARCHAR(10) | FK → school, NOT NULL |
| program_name | VARCHAR(100) | NOT NULL |
| degree_type | ENUM | NOT NULL |
| total_semesters | TINYINT | NOT NULL |
| total_credits | SMALLINT | NOT NULL |
| total_seats | SMALLINT | NOT NULL |

Degree types: `BS`, `BE`, `BBA`, `BArch`, `MS`, `PhD`
**11 programs seeded:** BSCS, BESE, BEE, BME, BIME, BBA, BSAF, BECE, BArch, BSAB, BChemE

---

#### course
| Column | Type | Constraints |
|--------|------|-------------|
| course_code | VARCHAR(10) | PK |
| school_id | VARCHAR(10) | FK → school, NOT NULL |
| course_title | VARCHAR(100) | NOT NULL |
| course_type | ENUM | NOT NULL |
| credit_hours | TINYINT | NOT NULL |
| contact_hours | TINYINT | NOT NULL |

Course types: `Theory`, `Lab`, `Theory+Lab`, `Studio`, `Seminar`
**15 courses seeded:** CS118, CS212, CS220, CS330, CS440, SE210, SE310, ME101, ME201, MGT101, FIN201, CE201, AR101, BS201, CHE201

---

#### prerequisite
| Column | Type | Constraints |
|--------|------|-------------|
| course_code | VARCHAR(10) | PK, FK → course |
| prereq_course_code | VARCHAR(10) | PK, FK → course |

CHECK: course_code ≠ prereq_course_code

---

#### program_course
| Column | Type | Constraints |
|--------|------|-------------|
| program_id | VARCHAR(10) | PK, FK → program |
| course_code | VARCHAR(10) | PK, FK → course |
| recommended_semester | TINYINT | NOT NULL |
| is_core | BOOLEAN | NOT NULL |

---

#### term
| Column | Type | Constraints |
|--------|------|-------------|
| term_id | VARCHAR(10) | PK |
| term_name | ENUM | NOT NULL |
| academic_year | SMALLINT | NOT NULL |
| start_date | DATE | NOT NULL |
| end_date | DATE | NOT NULL |

UNIQUE: (term_name, academic_year)
Term names: `Fall`, `Spring`, `Summer`
**10 terms seeded:** FA24 through SP28

---

#### classroom
| Column | Type | Constraints |
|--------|------|-------------|
| classroom_id | VARCHAR(15) | PK |
| building | VARCHAR(50) | NOT NULL |
| room_number | VARCHAR(10) | NOT NULL |
| capacity | SMALLINT | NOT NULL |

**12 classrooms seeded** across SEECS, SMME, NBS, SADA, NICE, ASAB, SCME blocks. Capacities: 30–100.

---

#### applicant
| Column | Type | Constraints |
|--------|------|-------------|
| applicant_id | VARCHAR(10) | PK |
| full_name | VARCHAR(100) | NOT NULL |
| cnic | VARCHAR(15) | NOT NULL, UNIQUE |
| email | VARCHAR(100) | NOT NULL, UNIQUE |
| high_school_board | ENUM | NOT NULL |
| high_school_score | DECIMAL(6,2) | CHECK 0–1100 |
| best_test_score | DECIMAL(5,2) | CHECK 0–200 |

Boards: `FBISE`, `AKU-EB`, `Cambridge`, `Other`
**15 applicants seeded** with realistic Pakistani names and CNICs

---

#### entry_test
| Column | Type | Constraints |
|--------|------|-------------|
| test_id | VARCHAR(15) | PK |
| academic_year | SMALLINT | NOT NULL |
| net_number | TINYINT | NOT NULL (1–4) |
| test_type | ENUM | NOT NULL |
| test_date | DATE | NOT NULL |
| total_marks | SMALLINT | DEFAULT 200 |

UNIQUE: (academic_year, net_number, test_type)
Test types: `Engineering`, `CS`, `Business`, `Architecture`, `Biosciences`, `Chemical`
**20 test sessions seeded** for 2025–2026

---

#### test_attempt
| Column | Type | Constraints |
|--------|------|-------------|
| applicant_id | VARCHAR(10) | PK, FK → applicant |
| test_id | VARCHAR(15) | PK, FK → entry_test |
| score | DECIMAL(5,2) | NOT NULL, CHECK 0–200 |

**15 attempts seeded** (one per applicant)

---

#### application
| Column | Type | Constraints |
|--------|------|-------------|
| application_id | VARCHAR(15) | PK |
| applicant_id | VARCHAR(10) | FK → applicant |
| program_id | VARCHAR(10) | FK → program |
| term_id | VARCHAR(10) | FK → term |
| snapshot_hs_score | DECIMAL(6,2) | |
| snapshot_best_test | DECIMAL(5,2) | |
| aggregate_score | DECIMAL(5,2) | |
| submission_date | DATE | NOT NULL |
| status | ENUM | NOT NULL |

UNIQUE: (applicant_id, program_id, term_id)
Status values: `Pending`, `Selected`, `Waitlisted`, `Rejected`, `Enrolled`, `Declined`
**20 applications seeded** with mixed statuses

---

#### offer
| Column | Type | Constraints |
|--------|------|-------------|
| offer_id | VARCHAR(15) | PK |
| application_id | VARCHAR(15) | FK → application, UNIQUE |
| issue_date | DATE | NOT NULL |
| expiry_date | DATE | NOT NULL |
| status | ENUM | NOT NULL |

Status values: `Issued`, `Accepted`, `Declined`, `Expired`
**12 offers seeded**

---

#### student
| Column | Type | Constraints |
|--------|------|-------------|
| student_id | VARCHAR(10) | PK |
| program_id | VARCHAR(10) | FK → program |
| applicant_id | VARCHAR(10) | FK → applicant, UNIQUE |
| full_name | VARCHAR(100) | NOT NULL |
| email | VARCHAR(100) | NOT NULL, UNIQUE |
| current_semester | TINYINT | NOT NULL |
| enrollment_date | DATE | NOT NULL |

**10 students seeded:** 5 from FA25 cohort (semester 2), 5 from FA26 cohort (semester 1)

---

#### section
| Column | Type | Constraints |
|--------|------|-------------|
| section_id | VARCHAR(15) | PK |
| course_code | VARCHAR(10) | FK → course |
| term_id | VARCHAR(10) | FK → term |
| classroom_id | VARCHAR(15) | FK → classroom |
| faculty_id | VARCHAR(15) | FK → faculty |
| section_label | VARCHAR(5) | NOT NULL |

UNIQUE: (course_code, term_id, section_label)
**17 sections seeded** across FA25, SP26, FA26

---

#### enrollment
| Column | Type | Constraints |
|--------|------|-------------|
| student_id | VARCHAR(10) | PK, FK → student |
| section_id | VARCHAR(15) | PK, FK → section |
| attendance_percentage | DECIMAL(5,2) | CHECK 0–100, nullable |
| grade | ENUM | nullable |

Grade values: `A`, `A-`, `B+`, `B`, `B-`, `C+`, `C`, `C-`, `D+`, `D`, `F`
NULL grade = course in progress
**28 enrollments seeded:** 12 completed (with grades), 16 in-progress

---

### 3.3 Views

#### student_transcript
```sql
SELECT s.student_id, s.full_name, s.program_id, p.program_name,
       c.course_code, c.course_title, t.term_name, t.academic_year,
       e.grade, e.attendance_percentage
FROM student s
JOIN program p ON s.program_id = p.program_id
JOIN enrollment e ON s.student_id = e.student_id
JOIN section sec ON e.section_id = sec.section_id
JOIN course c ON sec.course_code = c.course_code
JOIN term t ON sec.term_id = t.term_id;
```

#### classroom_utilization
```sql
SELECT cl.classroom_id, cl.building, cl.room_number, cl.capacity,
       COUNT(sec.section_id) AS sections_hosted
FROM classroom cl
LEFT JOIN section sec ON cl.classroom_id = sec.classroom_id
GROUP BY cl.classroom_id;
```

---

### 3.4 Triggers

#### enforce_class_capacity (BEFORE INSERT on enrollment)
Rejects the insert if the section's classroom is already at capacity.

```sql
DELIMITER //
CREATE TRIGGER enforce_class_capacity
BEFORE INSERT ON enrollment
FOR EACH ROW
BEGIN
  DECLARE room_cap INT;
  DECLARE cur_enrolled INT;
  SELECT cl.capacity INTO room_cap
  FROM section sec JOIN classroom cl ON sec.classroom_id = cl.classroom_id
  WHERE sec.section_id = NEW.section_id;
  SELECT COUNT(*) INTO cur_enrolled FROM enrollment WHERE section_id = NEW.section_id;
  IF cur_enrolled >= room_cap THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Enrollment failed: classroom capacity reached.';
  END IF;
END //
DELIMITER ;
```

#### auto_update_application_status (AFTER INSERT on student)
Promotes the matching application to `Enrolled` and the matching offer to `Accepted`.

```sql
DELIMITER //
CREATE TRIGGER auto_update_application_status
AFTER INSERT ON student
FOR EACH ROW
BEGIN
  UPDATE application
  SET status = 'Enrolled'
  WHERE applicant_id = NEW.applicant_id
    AND program_id = NEW.program_id
    AND status = 'Selected';

  UPDATE offer o
  JOIN application a ON o.application_id = a.application_id
  SET o.status = 'Accepted'
  WHERE a.applicant_id = NEW.applicant_id
    AND a.program_id = NEW.program_id
    AND o.status = 'Issued';
END //
DELIMITER ;
```

---

## 4. Design Rationale

See [Phase2_Design_Decisions.md](Phase2_Design_Decisions.md) for the full analysis. Key decisions summarised:

| Decision | Rationale |
|----------|-----------|
| VARCHAR PKs (SEECS, BSCS) | Human-readable; matches institutional codes; agent SQL is self-documenting |
| Student carries direct FKs to program and applicant | Eliminates unnecessary joins in the most common academic query paths |
| Courses owned by schools, not programs | Allows cross-program course sharing via program_course junction |
| Offer as separate entity from application | Separate lifecycles; one application can generate at most one offer |
| Snapshot columns on application | Immutable audit trail; scores at time of submission |
| best_test_score cache on applicant | Avoids correlated subquery on every aggregate score calculation |
| Capacity trigger not CHECK constraint | Aggregate rule (COUNT) cannot be expressed as a CHECK in MySQL |
| Status promotion trigger | Atomic consistency across application and offer on student creation |
| grade NULL for in-progress | Correct semantics; avoids polluting aggregate queries |
| Local LLM (Ollama) | Student PII stays within university network; no cloud API cost |
| FAISS few-shot threshold 0.35 | Injects examples only when relevant; avoids prompt bloat |
| Read-only enforcement (two layers) | System prompt + MySQL user privileges; defence in depth |

---

## 5. Key SQL Queries

These are the most illustrative queries the system generates, drawn from the few-shot examples.

### Q1: Program with most applications
```sql
SELECT p.program_name, COUNT(a.application_id) AS total_applications
FROM application a
JOIN program p ON a.program_id = p.program_id
GROUP BY a.program_id, p.program_name
ORDER BY total_applications DESC
LIMIT 5;
```

### Q2: Top 5 applicants by NET score
```sql
SELECT full_name, best_test_score
FROM applicant
ORDER BY best_test_score DESC
LIMIT 5;
```

### Q3: Full transcript for a student
```sql
SELECT c.course_title, t.term_name, t.academic_year, e.grade, e.attendance_percentage
FROM student s
JOIN enrollment e ON s.student_id = e.student_id
JOIN section sec ON e.section_id = sec.section_id
JOIN course c ON sec.course_code = c.course_code
JOIN term t ON sec.term_id = t.term_id
WHERE s.student_id = 'S001'
ORDER BY t.academic_year, t.term_name;
```

### Q4: Students currently in progress (grade NULL)
```sql
SELECT s.full_name, c.course_title
FROM enrollment e
JOIN student s ON e.student_id = s.student_id
JOIN section sec ON e.section_id = sec.section_id
JOIN course c ON sec.course_code = c.course_code
WHERE e.grade IS NULL;
```

### Q5: Rejected applicants who scored above 140
```sql
SELECT ap.full_name, ap.best_test_score
FROM application a
JOIN applicant ap ON a.applicant_id = ap.applicant_id
WHERE a.status = 'Rejected' AND ap.best_test_score > 140
ORDER BY ap.best_test_score DESC;
```

### Q6: Core courses for BSCS in first two semesters
```sql
SELECT c.course_title, pc.recommended_semester
FROM program_course pc
JOIN course c ON pc.course_code = c.course_code
WHERE pc.program_id = 'BSCS'
  AND pc.is_core = TRUE
  AND pc.recommended_semester <= 2
ORDER BY pc.recommended_semester;
```

### Q7: Faculty teaching most sections in Fall 2025
```sql
SELECT f.full_name, COUNT(sec.section_id) AS section_count
FROM section sec
JOIN faculty f ON sec.faculty_id = f.faculty_id
JOIN term t ON sec.term_id = t.term_id
WHERE t.term_name = 'Fall' AND t.academic_year = 2025
GROUP BY sec.faculty_id, f.full_name
ORDER BY section_count DESC
LIMIT 5;
```

### Q8: Applicants who scored above their test-type average
```sql
SELECT ap.full_name, ta.score, et.test_type,
       AVG(ta2.score) OVER (PARTITION BY et2.test_type) AS avg_for_type
FROM test_attempt ta
JOIN applicant ap ON ta.applicant_id = ap.applicant_id
JOIN entry_test et ON ta.test_id = et.test_id
WHERE ta.score > (
  SELECT AVG(ta2.score)
  FROM test_attempt ta2
  JOIN entry_test et2 ON ta2.test_id = et2.test_id
  WHERE et2.test_type = et.test_type
);
```

### Q9: Application-to-student conversion rate by school
```sql
SELECT sc.school_name,
       COUNT(DISTINCT a.application_id) AS total_applications,
       COUNT(DISTINCT st.student_id) AS enrolled_students
FROM school sc
JOIN program p ON sc.school_id = p.school_id
LEFT JOIN application a ON p.program_id = a.program_id
LEFT JOIN student st ON p.program_id = st.program_id
GROUP BY sc.school_id, sc.school_name
ORDER BY enrolled_students DESC;
```

### Q10: Courses with no sections in Fall 2025
```sql
SELECT c.course_code, c.course_title
FROM course c
WHERE c.course_code NOT IN (
  SELECT sec.course_code
  FROM section sec
  JOIN term t ON sec.term_id = t.term_id
  WHERE t.term_name = 'Fall' AND t.academic_year = 2025
);
```

---

## 6. Setup Guide

### 6.1 Prerequisites

- Python 3.11+
- Node.js 20+ and npm
- MySQL 8.0 (running, accessible)
- [Ollama](https://ollama.ai) installed and running

### 6.2 Ollama Setup

```bash
# Pull required models
ollama pull llama3.1
ollama pull nomic-embed-text

# Verify Ollama is running
curl http://localhost:11434/api/tags
```

### 6.3 Database Setup

```bash
# Connect to MySQL
mysql -u root -p

# Create database and load schema
CREATE DATABASE nust_university CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE nust_university;
SOURCE /path/to/test-sql-rag/db/NUST.sql;

# Verify tables loaded
SHOW TABLES;
-- Should show 16 tables
```

### 6.4 Backend Setup

```bash
cd test-sql-rag

# Create virtual environment
python -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env              # or create .env manually
```

Edit `.env`:
```
DB_HOST=localhost
DB_PORT=3306
DB_USER=your_mysql_user
DB_PASSWORD=your_mysql_password
DB_NAME=nust_university
OLLAMA_EMBED_MODEL=nomic-embed-text
```

```bash
# Start backend
python api.py
# Output: Application startup complete. → http://localhost:8000
```

### 6.5 Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Start dev server
npm run dev
# Output: → Local: http://localhost:5173
```

Open http://localhost:5173 in your browser.

### 6.6 Verify Everything Works

1. Open http://localhost:5173
2. Click the quick question: "Which program received the most applications?"
3. Wait ~5–15 seconds for the response
4. Click "Show reasoning" to verify SQL was generated correctly

---

## 7. User Guide

### 7.1 Asking Questions

Type your question in the input box at the bottom and press Enter (or click the send button). The agent will:
1. Determine which tables are relevant
2. Generate and validate SQL
3. Execute the query
4. Return a plain-English answer

**Good question types:**
- Counting and ranking: "How many students are enrolled in each program?"
- Filtering: "Which applicants were rejected despite scoring above 150?"
- Aggregation: "What is the average NET score by test type?"
- Specific lookups: "Show me the transcript for student S003."
- Comparisons: "Which program has the highest acceptance rate?"

**Tips:**
- Be specific about which term, year, or program you mean when it matters.
- If the answer seems wrong, click "Show reasoning" to inspect the SQL that was run.
- For complex multi-step questions, break them into simpler sub-questions.

### 7.2 Quick Questions

On first load, four pre-filled quick questions appear below the welcome message. Click any to submit it directly.

### 7.3 Schema Browsing

Type "show me the database schema" or "what tables exist" to get a structured list of all tables and their columns. This does not call the LLM — it directly queries the schema endpoint.

### 7.4 Viewing Reasoning Steps

Each AI response includes a "Show reasoning (N steps)" button. Clicking it reveals:
- **LLM thinking** (AIMessage): the agent's reasoning about which tables/queries to use
- **Tool calls** (ToolMessage): the SQL generated, the query checker result, and raw query output

This transparency lets you verify that the correct SQL was run and the answer is grounded in real data.

### 7.5 Out-of-Scope Questions

The agent only answers questions about NUST data. Questions about other universities, countries, or unrelated topics will receive the refusal message:

> "I am an assistant for the NUST University Database. I cannot answer questions unrelated to NUST admissions or academic data."

### 7.6 What You Cannot Do

- Modify any data (insert, update, delete) — the system is read-only
- Access financial records, research data, or HR payroll — not in scope
- Get real-time live data beyond the current database contents

---

## 8. API Reference

All endpoints are served at `http://localhost:8000`.

### POST /api/ask

Submit a natural language question.

**Request:**
```json
{
  "question": "Which program received the most applications?"
}
```

**Response:**
```json
{
  "answer": "Computer Science received the most applications with 6 in total...",
  "steps": [
    {
      "type": "AIMessage",
      "content": "I'll look at the application and program tables...",
      "tool_calls": [
        {"name": "sql_db_query", "args": {"query": "SELECT ..."}}
      ]
    },
    {
      "type": "ToolMessage",
      "tool_name": "sql_db_query",
      "content": "[('BS Computer Science', 6), ...]"
    }
  ]
}
```

**Error response (HTTP 500):**
```json
{
  "detail": "Agent error: ..."
}
```

---

### GET /api/tables

Returns all accessible table names.

**Response:**
```json
{
  "tables": ["applicant", "application", "classroom", "course", "enrollment",
             "entry_test", "faculty", "offer", "prerequisite", "program",
             "program_course", "school", "section", "student", "term", "test_attempt"]
}
```

---

### GET /api/schema

Returns the full schema as a table-to-columns mapping.

**Response:**
```json
{
  "schema": {
    "applicant": ["applicant_id", "full_name", "cnic", "email",
                  "high_school_board", "high_school_score", "best_test_score"],
    "course": ["course_code", "school_id", "course_title",
               "course_type", "credit_hours", "contact_hours"],
    "..."
  }
}
```

---

## 9. Troubleshooting

### Backend fails to start: "Can't connect to MySQL server"
- Verify MySQL is running: `mysql -u root -p -e "SHOW DATABASES;"`
- Check `.env` credentials match your MySQL configuration
- Confirm `nust_university` database exists: `SHOW DATABASES LIKE 'nust%';`

### Backend fails to start: "Connection refused: localhost:11434"
- Ollama is not running. Start it: `ollama serve` (or open the Ollama app)
- Pull the required model: `ollama pull llama3.1`

### Responses are very slow (> 30 seconds)
- Llama 3.1 on CPU-only hardware is slow. Expected: 10–15s on GPU, 30–60s on CPU.
- No workaround — reduce model size at the cost of accuracy (swap `llama3.1` for `llama3.2:1b` in `.env` for faster but less accurate results)

### Answer is blank or contains SQL/table output
- The `sanitize_final_answer()` function in `api.py` handles most leakage.
- If the model consistently leaks SQL, the system prompt's format rules need reinforcing for the specific query pattern.
- Add the failing question as a new few-shot example in `examples/examples.json` and restart the backend.

### Frontend shows "Network error"
- Backend is not running. Start with `python api.py`.
- Check the Vite proxy in `frontend/vite.config.js` points to the correct backend port (default: 8000).

### "Enrollment failed: classroom capacity reached" when loading seed data
- The trigger fires on INSERT. This is expected behaviour if you attempt to over-enroll.
- The seed data in `NUST.sql` is calibrated to not exceed capacity. If you see this error, the seed script may be running twice. Drop and recreate the database.
