import { createRoot } from "react-dom/client";
import { AppRoot } from "./App";
import "./styles/global.css";

const root = document.getElementById("root");
if (!root) throw new Error("Missing #root application element.");

createRoot(root).render(<AppRoot />);
