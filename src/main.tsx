import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";

const app = document.querySelector<HTMLDivElement>("#app");

if (app) {
  createRoot(app).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
}
