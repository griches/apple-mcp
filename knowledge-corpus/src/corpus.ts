import fs from "node:fs";
import path from "node:path";
import { parse as parseYaml } from "yaml";

type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface MarkdownSection {
  title: string;
  slug: string;
  level: number;
  content: string;
}

export interface SearchResult {
  scope: "corpus" | "report";
  section: string;
  location: string;
  snippet: string;
  score: number;
}

interface CorpusBundle {
  corpus: JsonObject;
  report: string | null;
  reportSections: MarkdownSection[];
  corpusPath: string;
  reportPath: string | null;
}

let cache: CorpusBundle | null = null;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asJsonValue(value: unknown): JsonValue {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map((item) => asJsonValue(item));
  }

  if (isRecord(value)) {
    return Object.fromEntries(
      Object.entries(value).map(([key, child]) => [key, asJsonValue(child)])
    );
  }

  return String(value);
}

function runtimeRoot(): string {
  return path.resolve(__dirname, "..");
}

function resolveCorpusPath(): string {
  return process.env.KNOWLEDGE_CORPUS_PATH
    ? path.resolve(process.env.KNOWLEDGE_CORPUS_PATH)
    : path.join(runtimeRoot(), "data", "mojosolo_operating_brain.json");
}

function resolveReportPath(): string | null {
  const configuredPath = process.env.KNOWLEDGE_REPORT_PATH;
  if (configuredPath) {
    return path.resolve(configuredPath);
  }

  const defaultReportPath = path.join(runtimeRoot(), "data", "mojosolo_operating_brain_report.md");
  if (fs.existsSync(defaultReportPath)) {
    return defaultReportPath;
  }

  const bundledPath = path.join(runtimeRoot(), "data", "deep-research-report.md");
  return fs.existsSync(bundledPath) ? bundledPath : null;
}

function parseStructuredCorpus(filePath: string): JsonObject {
  const raw = fs.readFileSync(filePath, "utf8");
  const extension = path.extname(filePath).toLowerCase();
  const parsed = extension === ".json" ? JSON.parse(raw) : parseYaml(raw);

  if (!isRecord(parsed)) {
    throw new Error(`Structured corpus at ${filePath} must parse to a top-level object.`);
  }

  return asJsonValue(parsed) as JsonObject;
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function extractMarkdownSections(markdown: string): MarkdownSection[] {
  const lines = markdown.split(/\r?\n/);
  const sections: MarkdownSection[] = [];
  let currentTitle = "Introduction";
  let currentLevel = 1;
  let currentContent: string[] = [];

  const pushSection = () => {
    const content = currentContent.join("\n").trim();
    if (!content && currentTitle === "Introduction") {
      return;
    }

    sections.push({
      title: currentTitle,
      slug: slugify(currentTitle),
      level: currentLevel,
      content,
    });
  };

  for (const line of lines) {
    const headingMatch = line.match(/^(#{1,6})\s+(.*)$/);
    if (headingMatch) {
      pushSection();
      currentLevel = headingMatch[1].length;
      currentTitle = headingMatch[2].trim();
      currentContent = [];
      continue;
    }

    currentContent.push(line);
  }

  pushSection();
  return sections;
}

function loadBundle(): CorpusBundle {
  if (cache) {
    return cache;
  }

  const corpusPath = resolveCorpusPath();
  const reportPath = resolveReportPath();
  const corpus = parseStructuredCorpus(corpusPath);
  const report = reportPath ? fs.readFileSync(reportPath, "utf8") : null;

  cache = {
    corpus,
    report,
    reportSections: report ? extractMarkdownSections(report) : [],
    corpusPath,
    reportPath,
  };

  return cache;
}

function normalizeText(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function buildSnippet(value: string, query: string, maxLength = 180): string {
  const normalizedValue = normalizeText(value);
  if (!normalizedValue) {
    return normalizedValue;
  }

  const normalizedQuery = query.toLowerCase();
  const index = normalizedValue.toLowerCase().indexOf(normalizedQuery);
  if (index === -1) {
    return normalizedValue.length <= maxLength
      ? normalizedValue
      : `${normalizedValue.slice(0, maxLength - 3).trim()}...`;
  }

  const start = Math.max(0, index - Math.floor((maxLength - query.length) / 2));
  const end = Math.min(normalizedValue.length, start + maxLength);

  return `${start > 0 ? "..." : ""}${normalizedValue.slice(start, end).trim()}${end < normalizedValue.length ? "..." : ""}`;
}

function previewValue(value: JsonValue): string {
  if (value === null) {
    return "null";
  }

  if (typeof value === "string") {
    return value;
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  if (Array.isArray(value)) {
    return `Array(${value.length})`;
  }

  const keys = Object.keys(value);
  const preview = Object.fromEntries(keys.slice(0, 4).map((key) => [key, value[key]]));
  return JSON.stringify(preview);
}

function getSectionNames(): string[] {
  return Object.keys(loadBundle().corpus);
}

function resolveSectionName(requestedName: string): string {
  const names = getSectionNames();
  const exact = names.find((name) => name === requestedName);
  if (exact) {
    return exact;
  }

  const normalized = requestedName.toLowerCase();
  const caseInsensitive = names.find((name) => name.toLowerCase() === normalized);
  if (caseInsensitive) {
    return caseInsensitive;
  }

  throw new Error(
    `Unknown corpus section "${requestedName}". Available sections: ${names.join(", ")}`
  );
}

function getSources(): JsonObject[] {
  const raw = loadBundle().corpus.source_registry;
  if (!Array.isArray(raw)) {
    return [];
  }

  return raw.filter((item): item is JsonObject => isRecord(item)).map((item) => item as JsonObject);
}

function resolveSourceId(requestedId: string): JsonObject {
  const sources = getSources();
  const exact = sources.find((source) => source.id === requestedId);
  if (exact) {
    return exact;
  }

  const normalized = requestedId.toLowerCase();
  const caseInsensitive = sources.find(
    (source) => typeof source.id === "string" && source.id.toLowerCase() === normalized
  );

  if (!caseInsensitive) {
    const availableIds = sources
      .map((source) => source.id)
      .filter((id): id is string => typeof id === "string");
    throw new Error(`Unknown source id "${requestedId}". Available ids: ${availableIds.join(", ")}`);
  }

  return caseInsensitive;
}

function resolveReportSection(requestedTitle: string): MarkdownSection {
  const sections = loadBundle().reportSections;
  if (!sections.length) {
    throw new Error("No research report is configured for this corpus.");
  }

  const requestedSlug = slugify(requestedTitle);
  const exact = sections.find(
    (section) => section.title === requestedTitle || section.slug === requestedSlug
  );
  if (exact) {
    return exact;
  }

  const normalized = requestedTitle.toLowerCase();
  const partial = sections.find(
    (section) =>
      section.title.toLowerCase() === normalized ||
      section.title.toLowerCase().includes(normalized) ||
      section.slug.includes(requestedSlug)
  );

  if (!partial) {
    const titles = sections.map((section) => section.title);
    throw new Error(
      `Unknown report section "${requestedTitle}". Available sections: ${titles.join(", ")}`
    );
  }

  return partial;
}

function scoreMatch(location: string, section: string, query: string, inValue: boolean): number {
  let score = 0;
  const normalizedQuery = query.toLowerCase();
  if (section.toLowerCase().includes(normalizedQuery)) {
    score += 2;
  }
  if (location.toLowerCase().includes(normalizedQuery)) {
    score += 3;
  }
  if (inValue) {
    score += 2;
  }
  return score;
}

function addMatch(map: Map<string, SearchResult>, result: SearchResult): void {
  const key = `${result.scope}:${result.section}:${result.location}`;
  const existing = map.get(key);
  if (!existing || result.score > existing.score) {
    map.set(key, result);
  }
}

function searchCorpusValue(
  value: JsonValue,
  sectionName: string,
  currentPath: string,
  query: string,
  matches: Map<string, SearchResult>
): void {
  const normalizedQuery = query.toLowerCase();

  if (value === null || typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    const text = String(value);
    const locationMatches = currentPath.toLowerCase().includes(normalizedQuery);
    const valueMatches = text.toLowerCase().includes(normalizedQuery);

    if (locationMatches || valueMatches) {
      addMatch(matches, {
        scope: "corpus",
        section: sectionName,
        location: currentPath,
        snippet: buildSnippet(valueMatches ? text : previewValue(value), query),
        score: scoreMatch(currentPath, sectionName, query, valueMatches),
      });
    }
    return;
  }

  if (Array.isArray(value)) {
    const locationMatches = currentPath.toLowerCase().includes(normalizedQuery);
    if (locationMatches) {
      addMatch(matches, {
        scope: "corpus",
        section: sectionName,
        location: currentPath,
        snippet: previewValue(value),
        score: scoreMatch(currentPath, sectionName, query, false),
      });
    }

    value.forEach((item, index) => {
      searchCorpusValue(item, sectionName, `${currentPath}[${index}]`, query, matches);
    });
    return;
  }

  const locationMatches = currentPath.toLowerCase().includes(normalizedQuery);
  if (locationMatches) {
    addMatch(matches, {
      scope: "corpus",
      section: sectionName,
      location: currentPath,
      snippet: previewValue(value),
      score: scoreMatch(currentPath, sectionName, query, false),
    });
  }

  Object.entries(value).forEach(([key, child]) => {
    const childPath = currentPath ? `${currentPath}.${key}` : key;
    searchCorpusValue(child, sectionName, childPath, query, matches);
  });
}

export function getCorpusOverview(): JsonObject {
  const bundle = loadBundle();
  const schema = isRecord(bundle.corpus.schema) ? (bundle.corpus.schema as JsonObject) : {};
  const machineIngestIndex = isRecord(bundle.corpus.machine_ingest_index)
    ? (bundle.corpus.machine_ingest_index as JsonObject)
    : {};
  const entityNames = Array.isArray(machineIngestIndex.entity_names)
    ? machineIngestIndex.entity_names.slice(0, 10)
    : [];

  return {
    corpus_name: schema.name ?? null,
    corpus_version: schema.version ?? null,
    generated_on: schema.generated_on ?? null,
    target_company: schema.target_company ?? null,
    target_domain: schema.target_domain ?? null,
    section_count: getSectionNames().length,
    sections: getSectionNames(),
    source_count: getSources().length,
    report_available: bundle.report !== null,
    report_section_count: bundle.reportSections.length,
    machine_ingest_entities: entityNames,
    corpus_path: bundle.corpusPath,
    report_path: bundle.reportPath,
  };
}

export function listCorpusSections(): JsonObject[] {
  const corpus = loadBundle().corpus;

  return getSectionNames().map((name) => {
    const value = corpus[name];
    const summary: JsonObject = {
      section: name,
      type: Array.isArray(value) ? "array" : typeof value,
    };

    if (Array.isArray(value)) {
      summary.item_count = value.length;
      summary.preview = previewValue(value);
      return summary;
    }

    if (isRecord(value)) {
      const keys = Object.keys(value);
      summary.key_count = keys.length;
      summary.keys = keys.slice(0, 8);

      if (typeof value.status === "string") {
        summary.status = value.status;
      }

      if (Array.isArray(value.evidence_source_ids)) {
        summary.evidence_source_count = value.evidence_source_ids.length;
      }

      if (Array.isArray(value.items)) {
        summary.item_count = value.items.length;
      }

      if (Array.isArray(value.templates)) {
        summary.template_count = value.templates.length;
      }

      if (Array.isArray(value.products)) {
        summary.product_count = value.products.length;
      }

      return summary;
    }

    summary.preview = value ?? null;
    return summary;
  });
}

export function getCorpusSection(sectionName: string): JsonValue {
  const resolvedName = resolveSectionName(sectionName);
  return loadBundle().corpus[resolvedName];
}

export function getObjectSection(sectionName: string): JsonObject {
  const value = getCorpusSection(sectionName);
  if (!isRecord(value)) {
    throw new Error(`Corpus section "${sectionName}" is not an object.`);
  }
  return value as JsonObject;
}

export function getMailIntelligenceConfig(): JsonObject {
  const value = getCorpusSection("mail_intelligence");
  if (!isRecord(value)) {
    throw new Error('Corpus section "mail_intelligence" is not an object.');
  }
  return value as JsonObject;
}

export function searchCorpus(
  query: string,
  options?: { scope?: "corpus" | "report" | "all"; section?: string; limit?: number }
): SearchResult[] {
  const scope = options?.scope ?? "all";
  const limit = options?.limit ?? 10;
  const matches = new Map<string, SearchResult>();

  if (scope === "all" || scope === "corpus") {
    const sectionNames = options?.section
      ? [resolveSectionName(options.section)]
      : getSectionNames();

    sectionNames.forEach((sectionName) => {
      const sectionValue = loadBundle().corpus[sectionName];
      searchCorpusValue(sectionValue, sectionName, sectionName, query, matches);
    });
  }

  if (scope === "all" || scope === "report") {
    loadBundle().reportSections.forEach((section) => {
      const titleMatches = section.title.toLowerCase().includes(query.toLowerCase());
      const contentMatches = section.content.toLowerCase().includes(query.toLowerCase());

      if (titleMatches || contentMatches) {
        addMatch(matches, {
          scope: "report",
          section: section.title,
          location: section.title,
          snippet: buildSnippet(
            titleMatches ? `${section.title}\n${section.content}` : section.content,
            query
          ),
          score: (titleMatches ? 5 : 0) + (contentMatches ? 2 : 0) + Math.max(0, 3 - section.level),
        });
      }
    });
  }

  return Array.from(matches.values())
    .sort((left, right) => right.score - left.score || left.location.localeCompare(right.location))
    .slice(0, limit);
}

export function listSources(): JsonObject[] {
  return getSources().map((source) => ({
    id: source.id ?? null,
    title: source.title ?? null,
    organization: source.organization ?? null,
    source_class: source.source_class ?? null,
    role_in_corpus: source.role_in_corpus ?? null,
    trust_level: source.trust_level ?? null,
    url: source.url ?? null,
  }));
}

export function getSource(sourceId: string): JsonObject {
  return resolveSourceId(sourceId);
}

export function listReportSections(): JsonObject[] {
  return loadBundle().reportSections.map((section) => ({
    title: section.title,
    slug: section.slug,
    level: section.level,
    word_count: section.content ? section.content.split(/\s+/).filter(Boolean).length : 0,
  }));
}

export function getReportSection(title: string): JsonObject {
  const section = resolveReportSection(title);
  return {
    title: section.title,
    slug: section.slug,
    level: section.level,
    content: section.content,
  };
}
