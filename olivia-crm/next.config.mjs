import { fileURLToPath } from "node:url";
/** @type {import('next').NextConfig} */
export default { outputFileTracingRoot: fileURLToPath(new URL(".", import.meta.url)) };
