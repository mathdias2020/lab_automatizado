import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Laboratório Automatizado · Control plane",
  description: "Acompanhamento auditável das execuções do laboratório.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
