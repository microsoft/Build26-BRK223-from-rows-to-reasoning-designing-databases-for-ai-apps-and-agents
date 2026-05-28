import React from "react";
import { Moon, Sun } from "lucide-react";


export function ThemeToggle({ theme, onToggle }) {
  const Icon = theme === "dark" ? Sun : Moon;
  return (
    <button className="iconButton" type="button" onClick={onToggle} aria-label="Toggle theme" title="Toggle theme">
      <Icon size={18} />
    </button>
  );
}