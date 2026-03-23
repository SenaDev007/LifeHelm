"use client";

import { useState } from "react";

export function VoiceInput({ onCommand }: { onCommand: (text: string) => void }) {
  const [isListening, setIsListening] = useState(false);

  return (
    <div style={{ marginTop: 18 }}>
      <button
        type="button"
        onClick={() => {
          // Placeholder: l'audio STT offline (Whisper) sera branché dans la phase suivante.
          setIsListening((v) => !v);
          onCommand("TODO_VOICE_COMMAND");
        }}
        style={{
          width: "100%",
          padding: "14px 16px",
          borderRadius: 16,
          border: "1px solid rgba(255,255,255,0.2)",
          background: "rgba(255,255,255,0.06)",
          color: "white",
          cursor: "pointer",
          fontWeight: 700,
        }}
      >
        {isListening ? "Écoute..." : "Micro"}
      </button>
    </div>
  );
}

