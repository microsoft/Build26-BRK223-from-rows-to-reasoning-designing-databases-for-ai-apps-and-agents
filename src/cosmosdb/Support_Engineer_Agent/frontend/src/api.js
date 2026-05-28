const API_BASE = import.meta.env.VITE_API_BASE || "http://localhost:8000";


async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(detail || `Request failed with ${response.status}`);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}


export const api = {
  configStatus: () => request("/api/config/status"),
  users: () => request("/api/users"),
  tickets: (userId) => request(`/api/users/${userId}/tickets`),
  profile: (userId) => request(`/api/users/${userId}/profile`),
  messages: (userId, threadId) => request(`/api/users/${userId}/tickets/${threadId}/messages`),
  createTicket: (userId, ticket) => request(`/api/users/${userId}/tickets`, {
    method: "POST",
    body: JSON.stringify(ticket),
  }),
  sendMessage: (userId, threadId, content) => request(`/api/users/${userId}/tickets/${threadId}/messages`, {
    method: "POST",
    body: JSON.stringify({ content }),
  }),
  process: (userId, threadId) => request(`/api/users/${userId}/tickets/${threadId}/process`, {
    method: "POST",
  }),
  seed: (process = false) => request(`/api/demo/seed?process=${process ? "true" : "false"}`, { method: "POST" }),
  reset: () => request("/api/demo/reset", { method: "POST" }),
};