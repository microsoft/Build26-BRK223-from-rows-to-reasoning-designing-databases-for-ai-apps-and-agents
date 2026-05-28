export const defaultPrompts = {
  "support-user-james": "This enrollment problem is back. What did we try last time?",
  "support-user-aayush": "Any update on the webhook issue?",
  "support-user-theo": "Why did our Cosmos DB queries slow down?",
  "support-user-raj": "Can you summarize the access-control concerns from last time?",
};


export const lifecyclePrompts = {
  "support-user-james": "Going forward, give me an executive-ready summary first, then the detailed troubleshooting steps.",
  "support-user-aayush": "For production incidents, I actually want a detailed incident report instead of the shortest answer.",
  "support-user-theo": "Please remember that dashboard fixes should optimize tenant-scoped reads before changing throughput.",
  "support-user-raj": "Please remember that every privileged-access answer must include approver, expiry, and audit evidence.",
};


export function loadTheme() {
  return localStorage.getItem("support-agent-theme") || "light";
}


export function saveTheme(theme) {
  localStorage.setItem("support-agent-theme", theme);
}