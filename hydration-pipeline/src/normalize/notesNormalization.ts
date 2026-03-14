import type { HarvestedNote, NotesHarvestResult } from "../providers/notesSource.js";

export interface NoteSignalDocument {
  id: string;
  sourceType: "note";
  sourceId: string;
  channel: string;
  authoredBy: "david" | "external" | "mixed" | "unknown";
  personaHint: "author" | "operator" | "machine" | "unknown";
  timestamp: string;
  rawDate: string;
  title: string;
  participants: string[];
  text: string;
  tags: string[];
  folder: string;
  provenance: {
    collector: string;
    directness: "direct" | "quoted" | "third_party" | "inferred";
    freshness: string;
  };
}

function stripHtml(html: string): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\r/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function parseTimestamp(rawDate: string): string {
  const parsed = Date.parse(rawDate);
  return Number.isNaN(parsed) ? rawDate : new Date(parsed).toISOString();
}

function derivePersonaHint(note: HarvestedNote): "author" | "operator" | "machine" | "unknown" {
  const haystack = `${note.folder} ${note.title} ${note.body}`.toLowerCase();
  if (haystack.includes("mojomosaic") || haystack.includes("daily intel") || haystack.includes("operator")) {
    return "operator";
  }
  if (haystack.includes("campaign") || haystack.includes("machine")) {
    return "machine";
  }
  return "author";
}

export function normalizeHarvestedNote(note: HarvestedNote): NoteSignalDocument {
  const personaHint = derivePersonaHint(note);
  return {
    id: `note:${note.folder}:${note.id}`,
    sourceType: "note",
    sourceId: note.id,
    channel: `notes:${personaHint}`,
    authoredBy: "david",
    personaHint,
    timestamp: parseTimestamp(note.modificationDate),
    rawDate: note.modificationDate,
    title: note.title,
    participants: ["david", note.folder],
    text: stripHtml(note.body),
    tags: ["notes", `folder:${note.folder}`, `persona:${personaHint}`].sort((left, right) => left.localeCompare(right)),
    folder: note.folder,
    provenance: {
      collector: "hydration-pipeline/notesSource",
      directness: "direct",
      freshness: new Date().toISOString(),
    },
  };
}

export function normalizeNotesHarvest(result: NotesHarvestResult): NoteSignalDocument[] {
  return result.harvestedNotes.map(normalizeHarvestedNote);
}

export function selectDavidFirstPersonNotes(documents: NoteSignalDocument[]): NoteSignalDocument[] {
  return documents.filter((document) => document.authoredBy === "david");
}
