"use client";

import { useRouter } from "next/navigation";
import { BigButton } from "@/components/accessible/BigButton";
import { VoiceInput } from "@/components/accessible/VoiceInput";

export default function AccessibleHomePage() {
  const router = useRouter();

  return (
    <div style={{ padding: 16, maxWidth: 520, margin: "0 auto" }}>
      <header style={{ padding: "20px 0 10px" }}>
        <div style={{ fontSize: 22, fontWeight: 900 }}>LifeHelm</div>
        <div style={{ opacity: 0.8, marginTop: 6 }}>{new Date().toLocaleDateString("fr-FR")}</div>
      </header>

      <div style={{ display: "grid", gap: 14 }}>
        <BigButton
          icon="💰"
          label="VENTE"
          color="green"
          onClick={() => router.push("/(accessible)/vente")}
        />
        <BigButton
          icon="🛒"
          label="DEPENSE"
          color="red"
          onClick={() => router.push("/(accessible)/depense")}
        />
        <BigButton icon="📊" label="BILAN" color="blue" onClick={() => router.push("/(accessible)/bilan")} />
      </div>

      <VoiceInput
        onCommand={(text) => {
          // Pour la V1 on route simplement.
          if (text.includes("vente")) router.push("/(accessible)/vente");
          else if (text.includes("depense")) router.push("/(accessible)/depense");
          else if (text.includes("bilan")) router.push("/(accessible)/bilan");
        }}
      />

      <div style={{ marginTop: 18, opacity: 0.75, fontSize: 13 }}>
        V1: interface accessible sans données vocales réelles (placeholder).
      </div>
    </div>
  );
}

