import React from "react";


export function UserSwitcher({ users, activeUserId, onSelect }) {
  return (
    <aside className="userRail" aria-label="Demo users">
      <div className="sectionLabel">Customers</div>
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