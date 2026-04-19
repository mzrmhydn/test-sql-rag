# NUST SQL RAG — NUST Database Assistant

A Retrieval-Augmented Generation (RAG) system that lets non-technical staff query a comprehensive NUST university management database using plain English. Ask questions about admissions, student records, courses, and more — no SQL knowledge required.

![Use Case Diagram](img/sql_usecase.png)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Database Schema](#database-schema)
- [Prerequisites — Fresh Windows Install](#prerequisites--fresh-windows-install)
  - [1. Git](#1-git)
  - [2. Python 3.11+](#2-python-311)
  - [3. Node.js & npm](#3-nodejs--npm)
  - [4. MySQL 8.0](#4-mysql-80)
  - [5. Ollama + Llama 3.1](#5-ollama--llama-31)
- [Project Setup](#project-setup)
  - [1. Clone the Repository](#1-clone-the-repository)
  - [2. Configure Environment Variables](#2-configure-environment-variables)
  - [3. Load the Database](#3-load-the-database)
  - [4. Set Up Python Backend](#4-set-up-python-backend)
  - [5. Set Up React Frontend](#5-set-up-react-frontend)
- [Running the Application](#running-the-application)
- [Usage](#usage)
- [API Reference](#api-reference)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)

---

## Overview

This system wraps a MySQL university database with an AI agent that:

- Converts natural language questions into valid SQL queries
- Executes those queries against a live MySQL database
- Formats results into human-readable answers
- Uses **semantic few-shot examples** (FAISS) to improve query generation
- **Self-corrects** bad SQL using a LangGraph ReAct reasoning loop
- Runs entirely **locally** — no cloud LLM API keys required (uses Ollama)

**Supported domains:** Admissions, Entry Tests, Programs, Courses, Students, Instructors, Fees, Enrollments, Classrooms, Terms.

**Security:** The agent is read-only — it can only run `SELECT` queries. No data can be modified through the chat interface.

---

## Architecture

```
Browser (React + Tailwind)
        │
        │  HTTP POST /api/ask
        ▼
FastAPI Backend (api.py :8000)
        │
        ├── FAISS Vector Store ──► Few-shot example retrieval
        │
        ├── LangGraph ReAct Agent
        │       ├── ChatOllama (llama3.1 @ localhost:11434)
        │       └── SQL Toolkit (list/describe/query tools)
        │
        └── SQLAlchemy ──► MySQL 8.0 (nust_university DB)
```

The agent uses a **ReAct loop**: it inspects the schema, generates SQL, validates syntax, executes, and retries on failure — all before returning an answer.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| LLM Runtime | Ollama (llama3.1 7B, local) |
| Agent Framework | LangGraph, LangChain |
| Embeddings / Vector Store | FAISS CPU |
| Backend API | FastAPI + Uvicorn |
| ORM / DB Driver | SQLAlchemy + PyMySQL |
| Database | MySQL 8.0 |
| Frontend | React 19, Vite 8, Tailwind CSS v4 |
| Language | Python 3.11+, JavaScript (JSX) |

---

## Database Schema

The `nust_university` database models the full student lifecycle across 15 tables:

**Admissions pipeline:** `Applicant` → `EntryTest` (via `TestScore`) → `Application` → `Student`

**Academic pipeline:** `School` → `Program` / `Course` (via `ProgramCourse`) → `Section` (per `Term`, `Instructor`, `Classroom`) → `Enrollment`

**Financials:** `Fee` table (unified ledger for application fees, tuition, hostel, library)

The schema includes check constraints, triggers (capacity enforcement, auto status updates), views (student transcript, classroom utilization), and stored procedures (admit student, generate challan). See [db/NUST.sql](db/NUST.sql) for the full definition.

---

## Prerequisites — Fresh Windows Install

Follow these steps in order on a fresh Windows 11 machine.

### 1. Git

Download and install from https://git-scm.com/download/win.

Accept all defaults. After installation, open **Git Bash** or **PowerShell** and verify:

```bash
git --version
# git version 2.x.x
```

### 2. Python 3.11+

Download the installer from https://www.python.org/downloads/.

> **Important:** On the first installer screen, check **"Add python.exe to PATH"** before clicking Install Now.

Verify in a new terminal:

```bash
python --version
# Python 3.11.x  (or higher)

pip --version
# pip 24.x ...
```

### 3. Node.js & npm

Download the LTS installer from https://nodejs.org/.

Accept all defaults. Verify:

```bash
node --version
# v22.x.x

npm --version
# 10.x.x
```

### 4. MySQL 8.0

Download **MySQL Installer** from https://dev.mysql.com/downloads/installer/.

Run the installer and choose:
- Setup Type: **Developer Default** (includes MySQL Server, Shell, Workbench)
- During configuration, set a **root password** — remember it, you will need it shortly
- Leave the port at **3306**
- Complete the installation and start the MySQL service

Verify (enter your root password when prompted):

```bash
mysql -u root -p --execute "SELECT VERSION();"
# 8.0.x
```

> **Tip:** If `mysql` is not recognised, add `C:\Program Files\MySQL\MySQL Server 8.0\bin` to your system PATH, or use the **MySQL Shell** shortcut installed alongside MySQL.

### 5. Ollama + Llama 3.1

Ollama runs the LLM locally. Download from https://ollama.com/download and run the installer.

After installation, open a terminal and pull the model (this downloads ~4.7 GB):

```bash
ollama pull llama3.1
```

Verify Ollama is running:

```bash
ollama list
# NAME            ID              SIZE    MODIFIED
# llama3.1:latest ...             4.7 GB  ...
```

Ollama starts automatically as a background service on Windows. If it is not running:

```bash
ollama serve
```

---

## Project Setup

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/test-sql-rag.git
cd test-sql-rag
```

### 2. Configure Environment Variables

Create a `.env` file in the project root:

```bash
# Git Bash / PowerShell
copy NUL .env        # Windows CMD
# or
touch .env           # Git Bash
```

Open `.env` in any text editor and paste the following, filling in your MySQL root password:

```dotenv
MYSQL_USER=root
MYSQL_PASSWORD=your_mysql_root_password_here
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_DB=nust_university
```

> **Optional — LangSmith tracing** (leave these out if you do not have an account):
> ```dotenv
> LANGSMITH_API_KEY=your_langsmith_key
> LANGCHAIN_TRACING_V2=true
> LANGCHAIN_PROJECT=SQL RAG Ollama
> ```

### 3. Load the Database

This creates the `nust_university` database and loads all tables, constraints, triggers, views, procedures, and seed data in one step:

```bash
mysql -u root -p < db/NUST.sql
```

Enter your MySQL root password when prompted. The import takes about 10–30 seconds.

Verify it worked:

```bash
mysql -u root -p --execute "USE nust_university; SHOW TABLES;"
```

You should see 15 tables listed (Applicant, Application, Classroom, Course, Enrollment, EntryTest, Fee, Instructor, Program, ProgramCourse, School, Section, Student, Term, TestScore).

### 4. Set Up Python Backend

Create and activate a virtual environment, then install dependencies:

```bash
# Create virtual environment
python -m venv venv

# Activate — Git Bash
source venv/Scripts/activate

# Activate — PowerShell
venv\Scripts\Activate.ps1
# If blocked by execution policy, run this first:
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Activate — Windows CMD
venv\Scripts\activate.bat

# Install all Python dependencies
pip install -r requirements.txt
```

This installs: FastAPI, Uvicorn, LangChain, LangGraph, langchain-ollama, FAISS-CPU, SQLAlchemy, PyMySQL, Pydantic, python-dotenv.

> **Note:** FAISS-CPU installation can take a few minutes and requires no GPU.

### 5. Set Up React Frontend

```bash
cd frontend
npm install
cd ..
```

---

## Running the Application

You need **two terminals** running simultaneously.

**Terminal 1 — Backend API**

Make sure your virtual environment is activated, then:

```bash
python api.py
```

Expected output:

```
INFO:     Started server process [...]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

The first startup takes 30–60 seconds as it connects to MySQL, initializes the Llama 3.1 model via Ollama, and builds the FAISS vector store from `examples/examples.json`.

**Terminal 2 — Frontend**

```bash
cd frontend
npm run dev
```

Expected output:

```
  VITE v8.x.x  ready in xxx ms

  ➜  Local:   http://localhost:5173/
```

Open your browser and navigate to **http://localhost:5173**

---

## Usage

Type any natural language question about NUST data into the chat box and press **Enter** (or click Send).

**Example questions:**

```
How many students are currently active?
List all programs offered by SEECS.
Which students have a CGPA above 3.5?
How many applications are pending for the Computer Science program?
What courses does the Software Engineering program require in semester 3?
Which instructors teach in the SMME school?
How much total fee has been collected for tuition payments?
List all classrooms with capacity greater than 50.
Which students are enrolled in CS101 this term?
What is the average entry test score for applicants to NBS programs?
```

Click the **reasoning steps** toggle (▶) under any response to see exactly how the agent generated and validated the SQL query.

---

## API Reference

### `POST /api/ask`

Ask a natural language question.

**Request body:**
```json
{
  "question": "How many active students are there?"
}
```

**Response:**
```json
{
  "answer": "There are 12 active students currently enrolled.",
  "steps": [
    {
      "type": "reasoning",
      "content": "I need to count students with Status = 'Active'..."
    },
    {
      "type": "tool_call",
      "content": "sql_db_query",
      "input": "SELECT COUNT(*) FROM Student WHERE Status = 'Active';"
    },
    {
      "type": "tool_result",
      "content": "[(12,)]"
    }
  ]
}
```

### `GET /api/tables`

List all tables in the database.

**Response:**
```json
{
  "tables": ["Applicant", "Application", "Classroom", "Course", "..."]
}
```

---

## Project Structure

```
test-sql-rag/
├── api.py                          # FastAPI backend — agent, LLM, SQL toolkit
├── requirements.txt                # Python dependencies
├── .env                            # Environment variables (not committed to git)
│
├── db/
│   ├── NUST.sql                    # Complete schema + seed data (15 tables)
│   └── ERD.mmd                     # Entity-relationship diagram (Mermaid)
│
├── examples/
│   ├── examples.json               # 22 few-shot Q&A pairs for FAISS retrieval
│   └── examples.sql                # Raw SQL examples
│
├── prompts/
│   └── system-prompt-template.txt  # LLM system prompt with schema instructions
│
├── frontend/
│   ├── package.json
│   ├── vite.config.js              # Vite + Tailwind + API proxy config
│   └── src/
│       ├── App.jsx                 # Main chat component
│       ├── App.css                 # Component styles
│       ├── index.css               # Global styles + design tokens
│       └── main.jsx                # React entry point
│
├── img/
│   └── sql_usecase.png             # Use case diagram
│
├── Phase1_Problem_and_Requirements.md
├── Phase2_Normalization_Analysis.md
└── Phase2_Relational_Schema.md
```

---

## Troubleshooting

**`mysql` command not found**

Add MySQL's bin directory to your PATH:
```
C:\Program Files\MySQL\MySQL Server 8.0\bin
```
Then restart your terminal.

---

**PowerShell blocks `Activate.ps1`**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

**`pip install` fails on FAISS**

Make sure you are using Python 3.11 or 3.12. FAISS-CPU does not support Python 3.13+ yet. Check with `python --version`.

---

**Backend cannot connect to MySQL**

- Confirm the MySQL service is running: open **Services** (`Win+R` → `services.msc`) and check **MySQL80**.
- Verify the password in `.env` matches what you set during MySQL installation.
- Test the connection directly: `mysql -u root -p`

---

**Ollama model not found or LLM errors**

```bash
# Check what models are available
ollama list

# Re-pull the model if missing
ollama pull llama3.1

# Start the Ollama server manually if the service is not running
ollama serve
```

---

**Frontend shows "Network Error" or blank responses**

- Confirm the backend is running on port 8000.
- Vite's proxy in `vite.config.js` forwards `/api/*` to `http://localhost:8000` — both servers must be up.
- Check the backend terminal for Python error messages.

---

**First query is very slow**

The first query after startup can take 20–60 seconds while Ollama loads the model weights into memory. Subsequent queries are significantly faster.
