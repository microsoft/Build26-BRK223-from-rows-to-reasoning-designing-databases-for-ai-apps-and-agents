import React, { useState } from "react";
import { Check, Plus, X } from "lucide-react";


export function TicketTimeline({ tickets, activeTicketId, onSelect, onCreate }) {
  const [creating, setCreating] = useState(false);
  const [title, setTitle] = useState("");
  const [product, setProduct] = useState("Product Adoption");
  const [priority, setPriority] = useState("Medium");

  async function submit(event) {
    event.preventDefault();
    if (!title.trim()) {
      return;
    }
    await onCreate({ title: title.trim(), product: product.trim() || "Product Adoption", priority });
    setTitle("");
    setProduct("Product Adoption");
    setPriority("Medium");
    setCreating(false);
  }

  return (
    <section className="timelinePanel">
      <div className="panelHeader inline">
        <div>
          <div className="sectionLabel">Engagement Timeline</div>
          <h2>Prior account work</h2>
        </div>
        <button className="iconButton muted" type="button" title="New engagement" aria-label="New engagement" onClick={() => setCreating((value) => !value)}>
          {creating ? <X size={16} /> : <Plus size={16} />}
        </button>
      </div>
      {creating && (
        <form className="ticketForm" onSubmit={submit}>
          <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Engagement title" />
          <input value={product} onChange={(event) => setProduct(event.target.value)} placeholder="Focus area" />
          <select value={priority} onChange={(event) => setPriority(event.target.value)}>
            <option>Low</option>
            <option>Medium</option>
            <option>High</option>
          </select>
          <button className="iconButton" type="submit" title="Create engagement" aria-label="Create engagement">
            <Check size={16} />
          </button>
        </form>
      )}
      <div className="ticketList">
        {tickets.map((ticket) => (
          <button
            className={`ticketItem ${ticket.id === activeTicketId ? "active" : ""}`}
            key={ticket.id}
            type="button"
            onClick={() => onSelect(ticket.id)}
          >
            <span className="ticketTitle">{ticket.title}</span>
            <span className="ticketMeta">
              <span className="badge">{ticket.product}</span>
              <span className={`badge priority-${(ticket.priority || "").toLowerCase()}`}>{ticket.priority}</span>
              <span className="badge status">{ticket.status}</span>
            </span>
          </button>
        ))}
      </div>
    </section>
  );
}