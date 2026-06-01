import React, { useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import { api } from "../api.js";
import { loadTheme, saveTheme } from "../state.js";
import { ChatPanel } from "./ChatPanel.jsx";
import { MemoryPanel } from "./MemoryPanel.jsx";
import { ThemeToggle } from "./ThemeToggle.jsx";
import { TicketTimeline } from "./TicketTimeline.jsx";
import { UserSwitcher } from "./UserSwitcher.jsx";


export function App() {
  const [theme, setTheme] = useState(loadTheme);
  const [users, setUsers] = useState([]);
  const [activeUserId, setActiveUserId] = useState("");
  const [tickets, setTickets] = useState([]);
  const [activeTicketId, setActiveTicketId] = useState("");
  const [messages, setMessages] = useState([]);
  const [profile, setProfile] = useState(null);
  const [latestRecall, setLatestRecall] = useState([]);
  const [config, setConfig] = useState(null);
  const [loading, setLoading] = useState(false);
  const [processing, setProcessing] = useState(false);
  const [status, setStatus] = useState("Ready");
  const [accountsCollapsed, setAccountsCollapsed] = useState(false);
  const [memoryCollapsed, setMemoryCollapsed] = useState(false);

  const activeUser = users.find((user) => user.id === activeUserId);
  const activeTicket = tickets.find((ticket) => ticket.id === activeTicketId);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    saveTheme(theme);
  }, [theme]);

  useEffect(() => {
    Promise.all([api.configStatus(), api.users()]).then(([configStatus, items]) => {
      setConfig(configStatus);
      setUsers(items);
      setActiveUserId(items[0]?.id || "");
      if (!configStatus.configured) {
        setStatus(`Missing env: ${configStatus.missing.join(", ")}`);
      }
    }).catch((error) => setStatus(error.message));
  }, []);

  useEffect(() => {
    if (!activeUserId) {
      return;
    }
    setStatus("Loading account memory...");
    Promise.all([api.tickets(activeUserId), api.profile(activeUserId)])
      .then(([ticketResponse, profileResponse]) => {
        const nextTickets = ticketResponse.tickets || [];
        setTickets(nextTickets);
        setActiveTicketId(nextTickets[0]?.id || "");
        setProfile(profileResponse);
        setLatestRecall([]);
        setStatus("Ready");
      })
      .catch((error) => setStatus(error.message));
  }, [activeUserId]);

  useEffect(() => {
    if (!activeUserId || !activeTicketId) {
      setMessages([]);
      return;
    }
    api.messages(activeUserId, activeTicketId)
      .then(setMessages)
      .catch((error) => setStatus(error.message));
  }, [activeUserId, activeTicketId]);

  async function refreshProfile() {
    if (!activeUserId) {
      return;
    }
    const nextProfile = await api.profile(activeUserId);
    setProfile(nextProfile);
  }

  async function sendMessage(content) {
    if (!activeUserId || !activeTicketId) {
      return;
    }
    setLoading(true);
    setMessages((current) => [...current, { role: "user", content, id: `local-${Date.now()}` }]);
    try {
      const result = await api.sendMessage(activeUserId, activeTicketId, content);
      setMessages((current) => [...current, { role: "agent", content: result.response, id: `agent-${Date.now()}` }]);
      setLatestRecall(result.recalled_memories || []);
      await refreshProfile();
      setStatus("Response stored in memory");
    } catch (error) {
      setStatus(error.message);
    } finally {
      setLoading(false);
    }
  }

  async function processMemory() {
    if (!activeUserId || !activeTicketId) {
      return;
    }
    setProcessing(true);
    setStatus("Processing memory...");
    try {
      await api.process(activeUserId, activeTicketId);
      await refreshProfile();
      setStatus("Memory processed");
    } catch (error) {
      setStatus(error.message);
    } finally {
      setProcessing(false);
    }
  }

  async function createTicket(ticket) {
    if (!activeUserId) {
      return;
    }
    setStatus("Creating engagement...");
    try {
      const created = await api.createTicket(activeUserId, ticket);
      setTickets((current) => [created, ...current]);
      setActiveTicketId(created.id);
      setMessages([]);
      setLatestRecall([]);
      setStatus("Engagement created");
    } catch (error) {
      setStatus(error.message);
    }
  }

  return (
    <div className="appShell">
      <header className="topBar">
        <div className="brand">
          <span className="brandMark" aria-hidden="true">
            <svg viewBox="0 0 18 18" role="img" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <linearGradient id="cosmosSphere" x1="9" y1="1.8" x2="9" y2="16.2" gradientUnits="userSpaceOnUse">
                  <stop stopColor="#5ea0ef" />
                  <stop offset="1" stopColor="#0f4faa" />
                </linearGradient>
              </defs>
              <circle cx="9" cy="9" r="6.6" fill="url(#cosmosSphere)" />
              <g stroke="#ffffff" strokeWidth="0.5" fill="none" opacity="0.92">
                <ellipse cx="9" cy="9" rx="6.6" ry="2.55" />
                <ellipse cx="9" cy="9" rx="2.55" ry="6.6" />
                <line x1="2.4" y1="9" x2="15.6" y2="9" />
                <line x1="9" y1="2.4" x2="9" y2="15.6" />
              </g>
              <g transform="rotate(-35 9 9)">
                <ellipse cx="9" cy="9" rx="8.05" ry="3.25" stroke="#83bdff" strokeWidth="0.7" fill="none" />
                <circle cx="9" cy="5.75" r="1.05" fill="#ffffff" />
              </g>
            </svg>
          </span>
          <div className="brandText">
            <div className="sectionLabel">Azure Cosmos DB Agent Memory</div>
            <h1>Customer Success Agent</h1>
          </div>
        </div>
        <div className="topActions">
          <span className="status"><RefreshCw size={14} className={processing ? "spin" : ""} />{status}</span>
          {config && <span className={`configPill ${config.configured ? "ready" : "missing"}`}>{config.configured ? "Connected" : "Config missing"}</span>}
          <ThemeToggle theme={theme} onToggle={() => setTheme(theme === "dark" ? "light" : "dark")} />
        </div>
      </header>

      <div className={`workspace${accountsCollapsed ? " accountsCollapsed" : ""}${memoryCollapsed ? " memoryCollapsed" : ""}`}>
        <UserSwitcher
          users={users}
          activeUserId={activeUserId}
          onSelect={setActiveUserId}
          collapsed={accountsCollapsed}
          onToggleCollapse={() => setAccountsCollapsed((value) => !value)}
        />
        <div className="centerStack">
          <ChatPanel user={activeUser} ticket={activeTicket} messages={messages} onSend={sendMessage} loading={loading} />
          <TicketTimeline tickets={tickets} activeTicketId={activeTicketId} onSelect={setActiveTicketId} onCreate={createTicket} />
        </div>
        <MemoryPanel
          profile={profile}
          latestRecall={latestRecall}
          onProcess={processMemory}
          processing={processing}
          user={activeUser}
          tickets={tickets}
          collapsed={memoryCollapsed}
          onToggleCollapse={() => setMemoryCollapsed((value) => !value)}
        />
      </div>
    </div>
  );
}