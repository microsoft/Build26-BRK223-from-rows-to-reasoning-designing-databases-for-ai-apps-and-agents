import React from "react";
import { Database, PanelRightClose, PanelRightOpen, RefreshCw } from "lucide-react";


function findEngagementTitle(tickets, threadId) {
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
                <span className={`memoryType type-${item.type || "memory"}`}>{item.type || "memory"}</span>
                {item.confidence !== null && item.confidence !== undefined && <span className="confidence">{Math.round(item.confidence * 100)}%</span>}
              </div>
              <p>{item.content}</p>
              {item.thread_id && <small>Source: {findEngagementTitle(tickets, item.thread_id)}</small>}
              {item.supersede_reason && <small>Superseded: {item.supersede_reason}</small>}
            </article>
          ))}
        </div>
      ) : null}
    </div>
  );
}


export function MemoryPanel({ profile, latestRecall, onProcess, processing, user, tickets, collapsed, onToggleCollapse }) {
  const profileContent = profile?.profile?.content || "Generate memory to build an account success profile.";
  if (collapsed) {
    return (
      <aside className="memoryPanel collapsed">
        <button
          className="iconButton collapseButton"
          type="button"
          onClick={onToggleCollapse}
          title="Expand Memory Inspector"
          aria-label="Expand Memory Inspector"
        >
          <PanelRightOpen size={17} />
        </button>
        <span className="railLabelVertical">Memory Inspector</span>
      </aside>
    );
  }
  return (
    <aside className="memoryPanel">
      <div className="panelHeader inline">
        <div>
          <div className="sectionLabel">Agent Memory Toolkit</div>
          <h2>Memory Inspector</h2>
        </div>
        <div className="panelHeaderActions">
          <button
            className="iconButton"
            type="button"
            onClick={onProcess}
            disabled={processing}
            title="Process memory: run extraction and summarization over this engagement's turns to derive facts, procedural/episodic memories, and updated thread + user summaries."
            aria-label="Process memory"
          >
            {processing ? <RefreshCw className="spin" size={17} /> : <Database size={17} />}
          </button>
          <button
            className="iconButton collapseButton"
            type="button"
            onClick={onToggleCollapse}
            title="Collapse Memory Inspector"
            aria-label="Collapse Memory Inspector"
          >
            <PanelRightClose size={17} />
          </button>
        </div>
      </div>

      <div className="profileBox">
        <span className="memoryType type-user_summary">user_summary</span>
        <p>{profileContent}</p>
        {user?.id && <small>Account memory scope: {user.id}</small>}
      </div>

      <MemoryList title="Recalled for latest answer" items={latestRecall} tickets={tickets} highlighted />
      <MemoryList title="Facts" items={profile?.facts || []} tickets={tickets} />
      <MemoryList title="Procedural" items={profile?.procedural || []} tickets={tickets} />
      <MemoryList title="Episodic" items={profile?.episodic || []} tickets={tickets} />
    </aside>
  );
}