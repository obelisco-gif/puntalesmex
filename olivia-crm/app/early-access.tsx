"use client";
import { useEffect, useState } from "react";
import { Contacts } from "./contacts";

type Stats = { total: number; email: number; phone: number; both: number; with_prior_purchase: number; without_identified_prior_purchase: number; unknown_registration_date: number };
type Props = { products: { id: string; name: string }[]; onSave: (resource: string, id: string, body: Record<string, unknown>) => Promise<boolean> };

export function EarlyAccess({ products, onSave }: Props) {
  const [stats, setStats] = useState<Stats | null>(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setError("");
    fetch("/api/early-access", { signal: controller.signal })
      .then(async response => { if (!response.ok) throw new Error("No se pudieron cargar las estadísticas."); return response.json(); })
      .then(setStats)
      .catch(err => { if (!controller.signal.aborted) setError(err.message); });
    return () => controller.abort();
  }, [revision]);
  return <>
    <div className="directory-intro"><p>Personas etiquetadas para el acceso prioritario de Black Friday.</p><button className="secondary" onClick={() => setRevision(value => value + 1)}>Actualizar estadísticas</button></div>
    {error ? <p role="alert">{error}</p> : !stats ? <p role="status">Cargando estadísticas…</p> : <div className="metrics">
      <article><span>Inscritos</span><strong>{stats.total}</strong><small>con la etiqueta de acceso prioritario</small></article>
      <article><span>Con email</span><strong>{stats.email}</strong><small>email registrado</small></article>
      <article><span>Con móvil</span><strong>{stats.phone}</strong><small>teléfono registrado</small></article>
      <article><span>Con ambos</span><strong>{stats.both}</strong><small>email y teléfono registrados</small></article>
    </div>}
    {stats && <><h2>Compras antes de la inscripción</h2><div className="metrics">
      <article><span>Con compras anteriores</span><strong>{stats.with_prior_purchase}</strong><small>pedidos identificados antes de apuntarse</small></article>
      <article><span>Sin compras identificadas</span><strong>{stats.without_identified_prior_purchase}</strong><small>no se ha encontrado una compra anterior</small></article>
      {stats.unknown_registration_date > 0 && <article><span>Fecha por confirmar</span><strong>{stats.unknown_registration_date}</strong><small>inscripciones sin fecha registrada</small></article>}
    </div><p>Según los pedidos de WooCommerce sincronizados y vinculados al contacto. Un pedido no identificado puede no estar sincronizado o no coincidir con sus datos.</p></>}
    <p>Los datos de contacto registrados no indican por sí solos el consentimiento para enviar comunicaciones.</p>
    <Contacts products={products} onSave={onSave} earlyAccess />
  </>;
}
