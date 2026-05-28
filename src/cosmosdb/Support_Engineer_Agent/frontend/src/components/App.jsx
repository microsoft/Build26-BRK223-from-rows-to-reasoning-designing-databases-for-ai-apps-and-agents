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
    setStatus("Loading customer memory...");
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
    setStatus("Creating ticket...");
    try {
      const created = await api.createTicket(activeUserId, ticket);
      setTickets((current) => [created, ...current]);
      setActiveTicketId(created.id);
      setMessages([]);
      setLatestRecall([]);
      setStatus("Ticket created");
    } catch (error) {
      setStatus(error.message);
    }
  }

  async function seedDemo() {
    setProcessing(true);
    setStatus("Seeding raw demo turns...");
    try {
      const result = await api.seed(false);
      if (activeUserId) {
        const [ticketResponse, profileResponse] = await Promise.all([api.tickets(activeUserId), api.profile(activeUserId)]);
        setTickets(ticketResponse.tickets || []);
        setActiveTicketId(ticketResponse.tickets?.[0]?.id || "");
        setProfile(profileResponse);
      }
      setStatus(result.status === "already_seeded" ? "Demo data already seeded" : "Raw demo turns seeded");
    } catch (error) {
      setStatus(error.message);
    } finally {
      setProcessing(false);
    }
  }

  async function resetDemo() {
    setProcessing(true);
    setStatus("Resetting demo memory...");
    try {
      const result = await api.reset();
      setMessages([]);
      setLatestRecall([]);
      await refreshProfile();
      setStatus(`Reset ${result.deleted} demo records`);
    } catch (error) {
      setStatus(error.message);
    } finally {
      setProcessing(false);
    }
  }

  return (
    <div className="appShell">
      <header className="topBar">
        <div>
          <div className="sectionLabel">Agent Memory Toolkit Sample</div>
          <h1>Support Engineer Agent</h1>
        </div>
        <div className="topActions">
          <span className="status"><RefreshCw size={14} className={processing ? "spin" : ""} />{status}</span>
          {config && <span className={`configPill ${config.configured ? "ready" : "missing"}`}>{config.configured ? "Config ready" : "Config missing"}</span>}
          <button className="seedButton" type="button" onClick={seedDemo} disabled={processing}>Seed Demo Data</button>
          <button className="seedButton secondary" type="button" onClick={resetDemo} disabled={processing}>Reset Memory</button>
          <ThemeToggle theme={theme} onToggle={() => setTheme(theme === "dark" ? "light" : "dark")} />
        </div>
      </header>

      <div className="workspace">
        <UserSwitcher users={users} activeUserId={activeUserId} onSelect={setActiveUserId} />
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
        />
      </div>
    </div>
  );
}