import React, { useState } from "react";
import { Repeat2, Send, Sparkles } from "lucide-react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { defaultPrompts, lifecyclePrompts } from "../state.js";


export function ChatPanel({ user, ticket, messages, onSend, loading }) {
  const [draft, setDraft] = useState("");
  const prompt = user ? defaultPrompts[user.id] : "";
  const lifecyclePrompt = user ? lifecyclePrompts[user.id] : "";

  function submit(event) {
    event.preventDefault();
    const content = draft.trim();
    if (!content || loading) {
      return;
    }
    setDraft("");
    onSend(content);
  }

  function usePrompt() {
    setDraft(prompt);
  }

  function useLifecyclePrompt() {
    setDraft(lifecyclePrompt);
  }

  return (
    <main className="chatPanel">
      <div className="chatHeader">
        <div>
          <div className="sectionLabel">Current Engagement</div>
          <h1>{ticket?.title || "Select an engagement"}</h1>
          <p>{[user?.name, user?.company, ticket?.product].filter((part, index, parts) => part && parts.indexOf(part) === index).join(" · ")}</p>
        </div>
      </div>

      <div className="messages" aria-live="polite">
        {messages.map((message, index) => (
          <article className={`message ${message.role}`} key={message.id || index}>
            <span>{message.role === "agent" ? "Agent" : "Account"}</span>
            <div className="messageBody">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>{message.content}</ReactMarkdown>
            </div>
          </article>
        ))}
        {loading && <article className="message agent pending"><span>Agent</span><p>Thinking with remembered account context...</p></article>}
      </div>

      <form className="composer" onSubmit={submit}>
        <textarea
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="Ask the Agent about this account's goals, risks, or prior engagements..."
          rows={2}
        />
        <div className="composerActions">
          <div className="sampleColumn">
            <button
              className="suggestButton"
              type="button"
              onClick={usePrompt}
              disabled={!prompt}
              title="Sample Q1 (Recall): insert a sample question that makes the agent retrieve this account's stored memories (facts, summaries, prior engagements) to answer."
            >
              <Sparkles size={16} />
              <span>Sample Q1</span>
            </button>
            <button
              className="suggestButton secondary"
              type="button"
              onClick={useLifecyclePrompt}
              disabled={!lifecyclePrompt}
              title="Sample Q2 (Lifecycle): insert a sample question about the account's journey over time, showing how memory evolves and is updated across engagements."
            >
              <Repeat2 size={16} />
              <span>Sample Q2</span>
            </button>
          </div>
          <button className="sendButton" type="submit" disabled={loading || !draft.trim()} title="Send message" aria-label="Send message">
            <Send size={18} />
          </button>
        </div>
      </form>
    </main>
  );
}