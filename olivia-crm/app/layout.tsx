import type { Metadata } from "next";
import "./styles.css";

export const metadata: Metadata = {
  title: "Olivia CRM · Sadiet",
  description: "Gestión comercial y conversaciones de Olivia."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="es"><body>{children}</body></html>;
}