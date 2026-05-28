import React, { useState } from "react";
import { Repeat2, Send, Sparkles } from "lucide-react";
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
          <div className="sectionLabel">Current Ticket</div>
          <h1>{ticket?.title || "Select a ticket"}</h1>
          <p>{user?.name} · {user?.company} · {ticket?.product}</p>
        </div>
        <div className="promptActions">
          <button className="suggestButton" type="button" onClick={usePrompt} disabled={!prompt}>
            <Sparkles size={16} />
            <span>Recall</span>
          </button>
          <button className="suggestButton secondary" type="button" onClick={useLifecyclePrompt} disabled={!lifecyclePrompt}>
            <Repeat2 size={16} />
            <span>Lifecycle</span>
          </button>
        </div>
      </div>

      <div className="messages" aria-live="polite">
        {messages.length ? messages.map((message, index) => (
          <article className={`message ${message.role}`} key={message.id || index}>
            <span>{message.role === "agent" ? "Agent" : "Customer"}</span>
            <p>{message.content}</p>
          </article>
        )) : (
          <div className="emptyChat">Seed demo data or send a message to start this ticket.</div>
        )}
        {loading && <article className="message agent pending"><span>Agent</span><p>Thinking with remembered support context...</p></article>}
      </div>

      <form className="composer" onSubmit={submit}>
        <textarea
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="Ask the Agent about this customer's support history..."
          rows={3}
        />
        <button className="sendButton" type="submit" disabled={loading || !draft.trim()} title="Send message" aria-label="Send message">
          <Send size={18} />
        </button>
      </form>
    </main>
  );
}