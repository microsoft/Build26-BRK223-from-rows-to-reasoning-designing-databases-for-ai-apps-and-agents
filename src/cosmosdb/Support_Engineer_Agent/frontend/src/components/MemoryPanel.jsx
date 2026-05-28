import React from "react";
import { Database, RefreshCw } from "lucide-react";


function findTicketTitle(tickets, threadId) {
  return tickets.find((ticket) => ticket.id === threadId)?.title || threadId;
}


function MemoryList({ title, items, tickets, highlighted }) {
  return (
    <div className="memoryBlock">
      <h3>{title}</h3>
      {items?.length ? (
        <div className="memoryList">
          {items.map((item, index) => (
            <article className={`memoryItem ${highlighted ? "highlighted" : ""}`} key={item.id || `${title}-${index}`}>
              <div className="memoryMetaRow">
                <span className="memoryType">{item.type || "memory"}</span>
                {item.confidence !== null && item.confidence !== undefined && <span className="confidence">{Math.round(item.confidence * 100)}%</span>}
              </div>
              <p>{item.content}</p>
              {item.thread_id && <small>Source: {findTicketTitle(tickets, item.thread_id)}</small>}
              {item.supersede_reason && <small>Superseded: {item.supersede_reason}</small>}
            </article>
          ))}
        </div>
      ) : (
        <p className="emptyState">No stored memory yet.</p>
      )}
    </div>
  );
}


export function MemoryPanel({ profile, latestRecall, onProcess, processing, user, tickets }) {
  const profileContent = profile?.profile?.content || "Generate memory to build a support profile for this customer.";
  return (
    <aside className="memoryPanel">
      <div className="panelHeader inline">
        <div>
          <div className="sectionLabel">Agent Memory Toolkit</div>
          <h2>Memory Inspector</h2>
        </div>
        <button className="iconButton" type="button" onClick={onProcess} disabled={processing} title="Process memory" aria-label="Process memory">
          {processing ? <RefreshCw className="spin" size={17} /> : <Database size={17} />}
        </button>
      </div>

      <div className="profileBox">
        <span className="memoryType">user_summary</span>
        <p>{profileContent}</p>
        {user?.id && <small>Memory scope: {user.id}</small>}
      </div>

      <MemoryList title="Recalled for latest answer" items={latestRecall} tickets={tickets} highlighted />
      <MemoryList title="Facts" items={profile?.facts || []} tickets={tickets} />
      <MemoryList title="Procedural" items={profile?.procedural || []} tickets={tickets} />
      <MemoryList title="Episodic" items={profile?.episodic || []} tickets={tickets} />
    </aside>
  );
}