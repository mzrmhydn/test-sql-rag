import { useState, useRef, useEffect } from 'react';
import './App.css';

function App() {
  const [messages, setMessages] = useState([
    {
      role: 'ai',
      content:
        "Hi! I'm your NUST University database assistant. Ask me anything about admissions, programs, students, courses, enrollments, fees, and more!",
    },
  ]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [showSteps, setShowSteps] = useState({});
  const messagesEndRef = useRef(null);
  const inputRef = useRef(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isLoading]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const SCHEMA_QUESTION = 'Show me the database schema';

  const isSchemaRequest = (q) => {
    const cleaned = q.trim().toLowerCase().replace(/[?.!,]/g, '');
    if (!/\bschemas?\b/.test(cleaned)) return false;
    const intentVerbs = /\b(show|get|give|list|display|describe|what|whats|fetch|see|view|print|return|provide|tell|share|explain|output)\b/;
    if (intentVerbs.test(cleaned)) return true;
    const words = cleaned.split(/\s+/).filter(Boolean);
    const fillers = new Set(['the', 'a', 'an', 'db', 'database', 'please', 'pls', 'me', 'my', 'our', 'your', 'of', 'for']);
    return words.every((w) => w === 'schema' || w === 'schemas' || fillers.has(w));
  };

  const sendQuestion = async () => {
    const question = input.trim();
    if (!question || isLoading) return;

    setInput('');
    setMessages((prev) => [...prev, { role: 'user', content: question }]);
    setIsLoading(true);

    try {
      if (isSchemaRequest(question)) {
        const response = await fetch('/api/schema');
        if (!response.ok) {
          throw new Error(`Server error: ${response.status}`);
        }
        const data = await response.json();
        const schemaText = Object.entries(data.schema || {})
          .map(([table, cols]) => `• ${table} (${cols.join(', ')})`)
          .join('\n');
        setMessages((prev) => [
          ...prev,
          {
            role: 'ai',
            content: schemaText
              ? `Here is a summary of the database schema:\n\n${schemaText}\n\nFeel free to ask questions about any of these tables or columns.`
              : 'No tables found in the database.',
          },
        ]);
        return;
      }

      const response = await fetch('/api/ask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question }),
      });

      if (!response.ok) {
        throw new Error(`Server error: ${response.status}`);
      }

      const data = await response.json();
      setMessages((prev) => [
        ...prev,
        {
          role: 'ai',
          content: data.answer || 'No answer returned.',
          steps: data.steps || [],
        },
      ]);
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        {
          role: 'ai',
          content: `Sorry, something went wrong: ${err.message}`,
          isError: true,
        },
      ]);
    } finally {
      setIsLoading(false);
      inputRef.current?.focus();
    }
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendQuestion();
    }
  };

  const toggleSteps = (index) => {
    setShowSteps((prev) => ({ ...prev, [index]: !prev[index] }));
  };

  const quickQuestions = [
    SCHEMA_QUESTION,
    'Which program received the most applications?',
    'List the top 5 applicants by NET score.',
    'How many students are enrolled in each program?',
  ];

  return (
    <div className="app-container">
      {/* Header */}
      <header className="app-header">
        <div className="header-content">
          <div className="header-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <ellipse cx="12" cy="5" rx="9" ry="3" />
              <path d="M3 5V19A9 3 0 0 0 21 19V5" />
              <path d="M3 12A9 3 0 0 0 21 12" />
            </svg>
          </div>
          <div>
            <h1 className="header-title">NUST DBS Agent</h1>
            <p className="header-subtitle">Chat with your Database · Powered by Ollama</p>
          </div>
        </div>
        <div className="status-badge">
          <span className="status-dot"></span>
          llama3.1
        </div>
      </header>

      {/* Messages Area */}
      <main className="messages-area">
        <div className="messages-container">
          {messages.map((msg, i) => (
            <div key={i} className={`message-row ${msg.role} animate-fade-in-up`} style={{ animationDelay: `${i * 0.05}s` }}>
              <div className={`message-bubble ${msg.role} ${msg.isError ? 'error' : ''}`}>
                {/* Avatar */}
                <div className={`avatar ${msg.role}`}>
                  {msg.role === 'ai' ? (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <ellipse cx="12" cy="5" rx="9" ry="3" />
                      <path d="M3 5V19A9 3 0 0 0 21 19V5" />
                      <path d="M3 12A9 3 0 0 0 21 12" />
                    </svg>
                  ) : (
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                      <circle cx="12" cy="7" r="4" />
                    </svg>
                  )}
                </div>

                {/* Content */}
                <div className="message-content">
                  <span className="message-label">{msg.role === 'ai' ? 'NUST DBS Agent' : 'You'}</span>
                  <p className="message-text">{msg.content}</p>

                  {/* Steps toggle */}
                  {msg.steps && msg.steps.length > 0 && (
                    <div className="steps-section">
                      <button className="steps-toggle" onClick={() => toggleSteps(i)}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ transform: showSteps[i] ? 'rotate(90deg)' : 'none', transition: 'transform 0.2s' }}>
                          <polyline points="9 18 15 12 9 6" />
                        </svg>
                        {showSteps[i] ? 'Hide' : 'Show'} reasoning ({msg.steps.filter(s => s.type !== 'HumanMessage').length} steps)
                      </button>

                      {showSteps[i] && (
                        <div className="steps-list">
                          {msg.steps
                            .filter((s) => s.type !== 'HumanMessage')
                            .map((step, j) => (
                              <div key={j} className="step-item">
                                <span className={`step-badge ${step.type === 'AIMessage' ? 'ai' : 'tool'}`}>
                                  {step.type === 'AIMessage' ? 'LLM' : step.tool_name || 'Tool'}
                                </span>
                                {step.tool_calls && step.tool_calls.map((tc, k) => (
                                  <div key={k} className="tool-call">
                                    <span className="tool-name">{tc.name}</span>
                                    {tc.args?.query && (
                                      <code className="tool-query">{tc.args.query}</code>
                                    )}
                                    {tc.args?.table_names && (
                                      <code className="tool-query">{tc.args.table_names}</code>
                                    )}
                                  </div>
                                ))}
                                {step.content && step.type === 'ToolMessage' && (
                                  <code className="tool-result">{step.content.substring(0, 300)}{step.content.length > 300 ? '...' : ''}</code>
                                )}
                              </div>
                            ))}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              </div>
            </div>
          ))}

          {/* Loading indicator */}
          {isLoading && (
            <div className="message-row ai animate-fade-in-up">
              <div className="message-bubble ai">
                <div className="avatar ai">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <ellipse cx="12" cy="5" rx="9" ry="3" />
                    <path d="M3 5V19A9 3 0 0 0 21 19V5" />
                    <path d="M3 12A9 3 0 0 0 21 12" />
                  </svg>
                </div>
                <div className="message-content">
                  <span className="message-label">NUST DBS Agent</span>
                  <div className="typing-indicator">
                    <span></span>
                    <span></span>
                    <span></span>
                  </div>
                </div>
              </div>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>
      </main>

      {/* Quick Questions */}
      {messages.length <= 1 && (
        <div className="quick-questions">
          {quickQuestions.map((q, i) => (
            <button key={i} className="quick-btn" onClick={() => { setInput(q); inputRef.current?.focus(); }}>
              {q}
            </button>
          ))}
        </div>
      )}

      {/* Input Area */}
      <footer className="input-area">
        <div className="input-container">
          <input
            ref={inputRef}
            type="text"
            className="chat-input"
            placeholder="Ask a question about the database..."
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={isLoading}
          />
          <button className="send-btn" onClick={sendQuestion} disabled={isLoading || !input.trim()}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="22" y1="2" x2="11" y2="13" />
              <polygon points="22 2 15 22 11 13 2 9 22 2" />
            </svg>
          </button>
        </div>
      </footer>
    </div>
  );
}

export default App;
