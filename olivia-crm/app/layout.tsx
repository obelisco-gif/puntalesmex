import type { Metadata } from "next";
import "./styles.css";
import "./auth.css";
import "./documentation.css";
import "./contacts.css";
import "./handoffs.css";
import "./variants.css";
import "./conversations.css";

export const metadata: Metadata = {
  title: "Olivia CRM · Sadiet",
  description: "Gestión comercial y conversaciones de Olivia."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="es"><body>{children}</body></html>;
}
