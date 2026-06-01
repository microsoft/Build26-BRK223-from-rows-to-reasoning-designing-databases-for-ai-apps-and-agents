export const defaultPrompts = {
  "success-account-northwind": "What risks should I mention in the Northwind renewal plan?",
  "success-account-contoso-health": "What security and compliance context should I remember for Contoso Health?",
  "success-account-fabrikam-retail": "Help me prepare the QBR adoption narrative for Fabrikam Retail.",
  "success-account-alpine-robotics": "What reliability context matters before Alpine's production launch?",
};


export const lifecyclePrompts = {
  "success-account-northwind": "Going forward, lead Northwind updates with executive-ready adoption metrics and finance-team risks.",
  "success-account-contoso-health": "Please remember that Contoso Health wants audit-ready evidence, not marketing language.",
  "success-account-fabrikam-retail": "Please remember that Fabrikam QBRs should connect adoption metrics to seasonal campaign outcomes.",
  "success-account-alpine-robotics": "Please remember that Alpine prefers direct technical detail unless an executive is in the meeting.",
};


export function loadTheme() {
  return localStorage.getItem("customer-success-agent-theme") || "light";
}


export function saveTheme(theme) {
  localStorage.setItem("customer-success-agent-theme", theme);
}