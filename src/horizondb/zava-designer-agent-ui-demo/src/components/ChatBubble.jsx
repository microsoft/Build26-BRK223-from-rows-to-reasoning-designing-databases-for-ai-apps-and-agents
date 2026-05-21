import { useState, useRef, useEffect } from 'react';

const WELCOME_MESSAGE = {
  role: 'assistant',
  text: "Hey! I can see your Brooklyn loft — love the chevron sofa and the brick walls. Tell me what you're looking for and I'll find pieces that fit perfectly.",
};

const SUGGESTED_PROMPTS = [
  'Mid-century coffee table under $300 and a cozy accent chair',
  'Bohemian rug and warm lighting to complement my couch',
  'Fill this room for under $2,000 — prioritize seating, tables, and lighting',
];

const THINKING_DELAY = 1500;

export default function ChatBubble({ onDesignReady, isDesigned }) {
  const [isOpen, setIsOpen] = useState(true); // start open
  const [messages, setMessages] = useState([WELCOME_MESSAGE]);
  const [input, setInput] = useState('');
  const [isThinking, setIsThinking] = useState(false);
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isOpen, isThinking]);

  const handlePrompt = (promptText) => {
    // Add user message
    setMessages((prev) => [...prev, { role: 'user', text: promptText }]);
    setIsThinking(true);

    // Simulate AI thinking, then respond + trigger design
    setTimeout(() => {
      setIsThinking(false);
      setMessages((prev) => [
        ...prev,
        {
          role: 'assistant',
          text: "Great taste! I searched our catalog and found 7 pieces that match your vibe — all under $625 total. I picked a VASAGLE coffee table, Art Leon swivel chair, and a HUGOAI mood lamp to start. Check out the picks on the right — you can add or remove anything.",
        },
      ]);
      onDesignReady();
    }, THINKING_DELAY);
  };

  const handleSend = () => {
    if (!input.trim() || isThinking) return;
    const text = input;
    setInput('');

    if (!isDesigned) {
      handlePrompt(text);
    } else {
      setMessages((prev) => [
        ...prev,
        { role: 'user', text },
      ]);
      setIsThinking(true);
      setTimeout(() => {
        setIsThinking(false);
        setMessages((prev) => [
          ...prev,
          {
            role: 'assistant',
            text: "Got it — I've updated the suggestions. Take a look!",
          },
        ]);
      }, THINKING_DELAY);
    }
  };

  const handleKey = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const showSuggestions = !isDesigned && messages.length === 1 && !isThinking;

  return (
    <>
      {/* Floating toggle button */}
      <button
        className={`chat-fab ${isOpen ? 'open' : ''}`}
        onClick={() => setIsOpen(!isOpen)}
        title="Chat with Zava Designer Agent"
      >
        {isOpen ? '✕' : '💬'}
      </button>

      {/* Chat panel */}
      {isOpen && (
        <div className="chat-panel">
          <div className="chat-panel-header">
            <img src="/zava-logo.png" alt="Zava" className="chat-panel-logo" />
            <div>
              <span className="chat-panel-title">Zava Designer Agent</span>
              <span className="chat-panel-status">● Online</span>
            </div>
          </div>

          <div className="chat-panel-messages">
            {messages.map((msg, i) => (
              <div key={i} className={`chat-msg ${msg.role}`}>
                {msg.role === 'assistant' && (
                  <span className="chat-msg-avatar">🏠</span>
                )}
                <div className="chat-msg-bubble">{msg.text}</div>
              </div>
            ))}

            {/* Thinking indicator */}
            {isThinking && (
              <div className="chat-msg assistant">
                <span className="chat-msg-avatar">🏠</span>
                <div className="chat-msg-bubble chat-thinking">
                  <span className="dot" />
                  <span className="dot" />
                  <span className="dot" />
                </div>
              </div>
            )}

            {/* Suggested prompts */}
            {showSuggestions && (
              <div className="chat-suggestions">
                {SUGGESTED_PROMPTS.map((prompt, i) => (
                  <button
                    key={i}
                    className="chat-suggestion-btn"
                    onClick={() => handlePrompt(prompt)}
                  >
                    {prompt}
                  </button>
                ))}
              </div>
            )}

            <div ref={bottomRef} />
          </div>

          <div className="chat-panel-input">
            <input
              type="text"
              placeholder={isDesigned ? 'Ask to swap items, change style...' : 'Describe what you want for your room...'}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKey}
              disabled={isThinking}
            />
            <button
              className="chat-send-btn"
              onClick={handleSend}
              disabled={!input.trim() || isThinking}
            >
              ↑
            </button>
          </div>
        </div>
      )}
    </>
  );
}
