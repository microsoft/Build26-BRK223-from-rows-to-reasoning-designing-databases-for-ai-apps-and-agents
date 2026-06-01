import React from "react";
import { PanelLeftClose, PanelLeftOpen } from "lucide-react";


export function UserSwitcher({ users, activeUserId, onSelect, collapsed, onToggleCollapse }) {
  if (collapsed) {
    return (
      <aside className="userRail collapsed" aria-label="Demo accounts">
        <button
          className="iconButton collapseButton"
          type="button"
          onClick={onToggleCollapse}
          title="Expand accounts"
          aria-label="Expand accounts"
        >
          <PanelLeftOpen size={17} />
        </button>
        <span className="railLabelVertical">Accounts</span>
      </aside>
    );
  }

  return (
    <aside className="userRail" aria-label="Demo accounts">
      <div className="panelHeader inline accountsHeader">
        <button
          className="iconButton collapseButton"
          type="button"
          onClick={onToggleCollapse}
          title="Collapse accounts"
          aria-label="Collapse accounts"
        >
          <PanelLeftClose size={17} />
        </button>
        <h2>Accounts</h2>
      </div>
      <div className="userList">
        {users.map((user) => (
          <button
            className={`userCard ${user.id === activeUserId ? "active" : ""}`}
            key={user.id}
            type="button"
            style={{ "--user-accent": user.accent }}
            onClick={() => onSelect(user.id)}
          >
            <span className="avatar" aria-hidden="true">{user.name.slice(0, 1)}</span>
            <span className="userText">
              <strong>{user.name}</strong>
              <small>{user.role}</small>
            </span>
          </button>
        ))}
      </div>
    </aside>
  );
}