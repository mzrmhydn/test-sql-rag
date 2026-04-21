"""
API Server — FastAPI backend for SQL RAG (Ollama Edition).

Exposes a POST /api/ask endpoint that accepts a question and returns
the agent's answer.

Usage:
    python api.py
"""

import json
import os
import re

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from langchain_community.agent_toolkits import SQLDatabaseToolkit
from langchain_community.utilities import SQLDatabase
from langchain_community.vectorstores import FAISS
from langchain_core.example_selectors import SemanticSimilarityExampleSelector
from langchain_core.messages import SystemMessage
from langchain_core.prompts import PromptTemplate
from langchain_ollama import ChatOllama, OllamaEmbeddings
from langgraph.prebuilt import create_react_agent
from pydantic import BaseModel
from sqlalchemy import inspect as sa_inspect

# ── Load environment variables ──────────────────────────────────────────
_ = load_dotenv()

# ── FastAPI App ─────────────────────────────────────────────────────────
app = FastAPI(title="SQL RAG API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Request / Response Models ───────────────────────────────────────────
class QuestionRequest(BaseModel):
    question: str


class AnswerResponse(BaseModel):
    answer: str
    steps: list[dict] = []


# ── Global state (initialized on startup) ──────────────────────────────
agent = None
database = None
fewshot_vectorstore = None

# Similarity threshold for few-shot injection.
# FAISS uses L2 distance: lower = more similar.
# Only inject few-shot examples when the best match is below this value.
FEWSHOT_SIMILARITY_THRESHOLD = 0.35


def build_user_input(question: str) -> str:
    """Embed the question once, decide whether to inject few-shot examples,
    and build the final user input string.

    Examples are attached as a reference block for the agent's internal use.
    We explicitly avoid the "Question: ... SQL query: " completion-template
    format, which causes small tool-calling models (e.g. llama3.1) to answer
    with free-text SQL instead of invoking the sql_db_query tool.
    """
    if fewshot_vectorstore is None:
        return question
    results = fewshot_vectorstore.similarity_search_with_score(question, k=4)
    if not results or results[0][1] >= FEWSHOT_SIMILARITY_THRESHOLD:
        return question

    reference_lines = []
    for doc, _ in results:
        q = doc.metadata.get("question", doc.page_content)
        sql = doc.metadata.get("query", "")
        reference_lines.append(f"- Similar question: {q}\n  Reference SQL: {sql}")
    reference_block = "\n".join(reference_lines)

    return (
        f"User question: {question}\n\n"
        "The following reference SQL snippets are for your internal guidance "
        "only. They may or may not match the user's intent — adapt as needed. "
        "Do not quote them to the user, do not echo any SQL in your final "
        "answer, and always execute your chosen query with the sql_db_query "
        "tool before answering.\n\n"
        f"{reference_block}"
    )


# ── Final-answer sanitizer ─────────────────────────────────────────────
_SQL_FENCE_RE = re.compile(r"```(?:sql|mysql)?\s*.*?```", re.DOTALL | re.IGNORECASE)
_PIPE_TABLE_LINE_RE = re.compile(r"^\s*\+[-+]+\+\s*$|^\s*\|.*\|\s*$")
_PREAMBLE_RE = re.compile(
    r"^(to answer (the|this|your) (user'?s )?question[^\n]*\.?\s*)+",
    re.IGNORECASE,
)
_LETS_RE = re.compile(
    r"^(let'?s (use|run|execute|double[- ]?check)[^\n]*\.?\s*)+",
    re.IGNORECASE,
)
_HERE_IS_QUERY_RE = re.compile(
    r"^(here(?:'s| is) (the|a|my) (mysql )?query[^\n]*:?\s*)+",
    re.IGNORECASE,
)


def _strip_pipe_tables(text: str) -> str:
    """Remove ASCII/markdown pipe-tables — the model sometimes inlines a fake
    rendering of the tool result. The real data is already in the steps."""
    kept = []
    for line in text.splitlines():
        if _PIPE_TABLE_LINE_RE.match(line):
            continue
        kept.append(line)
    return "\n".join(kept)


def sanitize_final_answer(text: str) -> str:
    """Remove reasoning artifacts that leak into the final AIMessage.

    The agent prompt forbids SQL, code fences, pipe tables, and "To answer…"
    preambles, but small local models don't always obey. This is the last
    line of defense before the answer reaches the user.
    """
    if not text:
        return text

    cleaned = _SQL_FENCE_RE.sub("", text)
    cleaned = _strip_pipe_tables(cleaned)

    # Drop leading preamble sentences iteratively.
    prev = None
    while prev != cleaned:
        prev = cleaned
        cleaned = cleaned.lstrip()
        cleaned = _PREAMBLE_RE.sub("", cleaned)
        cleaned = _LETS_RE.sub("", cleaned)
        cleaned = _HERE_IS_QUERY_RE.sub("", cleaned)

    # Collapse runs of blank lines.
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()
    return cleaned


@app.on_event("startup")
def startup():
    """Initialize agent and tools when the server starts."""
    global agent, database, fewshot_vectorstore

    print("Loading database...", end=" ", flush=True)
    mysql_user = os.getenv("MYSQL_USER", "root")
    mysql_password = os.getenv("MYSQL_PASSWORD", "")
    mysql_host = os.getenv("MYSQL_HOST", "localhost")
    mysql_port = os.getenv("MYSQL_PORT", "3306")
    mysql_db = os.getenv("MYSQL_DB", "nust_university")
    mysql_uri = (
        f"mysql+pymysql://{mysql_user}:{mysql_password}"
        f"@{mysql_host}:{mysql_port}/{mysql_db}"
    )
    database = SQLDatabase.from_uri(mysql_uri)
    print("OK")

    print("Loading LLM (llama3.1 via Ollama)...", end=" ", flush=True)
    llm = ChatOllama(model="llama3.1", temperature=0)
    print("OK")

    print("Setting up SQL toolkit...", end=" ", flush=True)
    toolkit = SQLDatabaseToolkit(db=database, llm=llm)
    tools = toolkit.get_tools()
    print("OK")

    system_prompt = PromptTemplate.from_file(
        template_file="prompts/system-prompt-template.txt"
    )
    system_message = SystemMessage(
        content=system_prompt.format(
            schema=database.get_table_info()
        )
    )

    print("Creating agent...", end=" ", flush=True)
    agent = create_react_agent(
        model=llm,
        tools=tools,
        prompt=system_message,
    )
    print("OK")

    print("Loading few-shot examples...", end=" ", flush=True)
    with open("examples/examples.json", encoding="utf-8") as f:
        examples = json.load(f)

    embed_model = os.getenv("OLLAMA_EMBED_MODEL", "llama3.1")
    embeddings = OllamaEmbeddings(model=embed_model)

    example_selector = SemanticSimilarityExampleSelector.from_examples(
        examples=examples,
        embeddings=embeddings,
        vectorstore_cls=FAISS,
        k=4,
        input_keys=["question"],
    )
    fewshot_vectorstore = example_selector.vectorstore
    print("OK")

    print("\n[OK] API server ready!\n")


@app.post("/api/ask", response_model=AnswerResponse)
def ask_question(req: QuestionRequest):
    """Answer a natural language question about the database."""
    question = req.question.strip()

    user_input = build_user_input(question)

    inputs = {"messages": [("human", user_input)]}

    final_answer = ""
    steps = []

    for chunk in agent.stream(input=inputs, stream_mode="values"):
        message = chunk["messages"][-1]

        # Collect reasoning steps
        msg_type = type(message).__name__
        content = getattr(message, "content", "")
        tool_calls = getattr(message, "tool_calls", [])
        name = getattr(message, "name", None)

        step = {"type": msg_type}
        if content:
            step["content"] = content
        if tool_calls:
            step["tool_calls"] = [
                {"name": tc.get("name", ""), "args": tc.get("args", {})}
                for tc in tool_calls
            ]
        if name:
            step["tool_name"] = name
        steps.append(step)

        # The last AI message without tool calls is the final answer
        if content and not tool_calls:
            if msg_type == "AIMessage":
                final_answer = content

    return AnswerResponse(
        answer=sanitize_final_answer(final_answer),
        steps=steps,
    )


@app.get("/api/tables")
def get_tables():
    """Return the list of available tables."""
    return {"tables": database.get_usable_table_names()}


@app.get("/api/schema")
def get_schema():
    """Return a summarized schema: each table mapped to its column names."""
    inspector = sa_inspect(database._engine)
    schema = {
        table_name: [col["name"] for col in inspector.get_columns(table_name)]
        for table_name in database.get_usable_table_names()
    }
    return {"schema": schema}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
