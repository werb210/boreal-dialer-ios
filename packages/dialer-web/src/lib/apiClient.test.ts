import { describe, it, expect } from "vitest";
import { buildUrl } from "./apiClient";
describe("buildUrl", () => { it("preserves the path and appends query params", () => { const url = buildUrl("/api/crm/contacts", { pageSize: 10, search: "todd" }); expect(url).toContain("/api/crm/contacts"); expect(url).toContain("pageSize=10"); expect(url).toContain("search=todd"); }); it("omits undefined and empty query values", () => { const url = buildUrl("/api/crm/contacts", { search: "", pageSize: undefined }); expect(url).not.toContain("search="); expect(url).not.toContain("pageSize="); }); });
