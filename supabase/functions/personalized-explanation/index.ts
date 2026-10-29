import { createServiceDependencies } from "../_shared/backend.ts";
import { createAIHandler } from "../_shared/handler.ts";

const dependencies = createServiceDependencies((name) => Deno.env.get(name));
Deno.serve(createAIHandler("explanation", dependencies));
