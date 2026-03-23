"use client";

export type BigButtonProps = {
  icon: string;
  label: string;
  color: "green" | "red" | "blue";
  onClick: () => void;
};

const colorMap: Record<BigButtonProps["color"], string> = {
  green: "linear-gradient(180deg, rgba(34,197,94,0.95), rgba(22,163,74,0.95))",
  red: "linear-gradient(180deg, rgba(239,68,68,0.95), rgba(220,38,38,0.95))",
  blue: "linear-gradient(180deg, rgba(59,130,246,0.95), rgba(37,99,235,0.95))",
};

export function BigButton({ icon, label, color, onClick }: BigButtonProps) {
  return (
    <button
      onClick={onClick}
      style={{
        background: colorMap[color],
        border: "none",
        borderRadius: 24,
        padding: 18,
        color: "white",
        fontWeight: 800,
        cursor: "pointer",
        minHeight: 120,
        display: "grid",
        gridTemplateColumns: "1fr auto",
        gap: 12,
        alignItems: "center",
      }}
    >
      <div style={{ fontSize: 22 }}>{label}</div>
      <div style={{ fontSize: 42, lineHeight: 1 }}>{icon}</div>
    </button>
  );
}

