import { extractText, parseToolResult, type McpSession, type McpToolResult } from "../mcp/client.js";
import { connectToServer } from "../mcp/localServers.js";
import { bootstrapCorpusContext, type CorpusBootstrapSnapshot, type MailIntelligenceAccount, type MailIntelligenceSourceRule } from "./corpusSource.js";

export interface DiscoveredMailAccount {
  name: string;
  emails: string[];
}

export interface MailboxInventoryRecord {
  name: string;
  account: string;
  unreadCount: number;
}

export interface MailMessageSummary {
  id: number;
  subject: string;
  sender: string;
  date: string;
  isRead: boolean;
}

export interface MailMessageDetail {
  id: number;
  subject: string;
  sender: string;
  date: string;
  isRead: boolean;
  content: string;
  toRecipients: string[];
  ccRecipients: string[];
}

export interface ResolvedMailAccount {
  configuredAccount: string;
  actualAccountName: string;
  emails: string[];
  mailbox: string;
  sentMailbox: string | null;
  personaId: string;
  persona: string;
  role: string;
  summary: string;
  primaryReplyFrom: boolean;
  catchAll: boolean;
  defaultLane: string;
  sourceRules: MailIntelligenceSourceRule[];
}

export interface HarvestedMailMessage {
  id: number;
  subject: string;
  sender: string;
  date: string;
  isRead: boolean;
  content: string;
  toRecipients: string[];
  ccRecipients: string[];
  configuredAccount: string;
  actualAccountName: string;
  accountEmails: string[];
  mailbox: string;
  personaId: string;
  persona: string;
  role: string;
  summary: string;
  defaultLane: string;
  primaryReplyFrom: boolean;
  catchAll: boolean;
  direction: "inbound" | "outbound";
  matchedRules: MailIntelligenceSourceRule[];
}

export interface MailHarvestAccountResult {
  account: ResolvedMailAccount;
  inboxMessages: HarvestedMailMessage[];
  sentMessages: HarvestedMailMessage[];
}

export interface MailHarvestResult {
  capturedAt: string;
  bootstrap: CorpusBootstrapSnapshot;
  discoveredAccounts: DiscoveredMailAccount[];
  mailboxInventory: MailboxInventoryRecord[];
  accounts: MailHarvestAccountResult[];
  errors: string[];
}

export interface HarvestMailOptions {
  bootstrap?: CorpusBootstrapSnapshot;
  env?: Record<string, string>;
  inboxLimit?: number;
  sentLimit?: number;
  includeSent?: boolean;
}

interface ToolCaller {
  callTool(name: string, args?: Record<string, unknown>): Promise<McpToolResult>;
}

function requireParsedResult<T>(label: string, result: McpToolResult): T {
  const parsed = parseToolResult<T>(result);
  if (parsed !== null) {
    return parsed;
  }

  throw new Error(`[MailSource] Failed to parse ${label}. Raw result: ${extractText(result) || "<empty>"}`);
}

export async function loadDiscoveredMailAccounts(session: ToolCaller): Promise<DiscoveredMailAccount[]> {
  return requireParsedResult<DiscoveredMailAccount[]>(
    "mail-intelligence:discover_mail_accounts",
    await session.callTool("discover_mail_accounts"),
  );
}

export async function loadMailboxInventory(session: ToolCaller): Promise<MailboxInventoryRecord[]> {
  return requireParsedResult<MailboxInventoryRecord[]>("apple-mail:list_mailboxes", await session.callTool("list_mailboxes"));
}

export async function listMailboxMessages(
  session: ToolCaller,
  mailbox: string,
  account: string,
  limit: number,
): Promise<MailMessageSummary[]> {
  return requireParsedResult<MailMessageSummary[]>(
    `apple-mail:list_messages(${account}/${mailbox})`,
    await session.callTool("list_messages", { mailbox, account, limit }),
  );
}

export async function getMailboxMessage(
  session: ToolCaller,
  mailbox: string,
  account: string,
  messageId: number,
): Promise<MailMessageDetail> {
  return requireParsedResult<MailMessageDetail>(
    `apple-mail:get_message(${account}/${mailbox}/${messageId})`,
    await session.callTool("get_message", { mailbox, account, message_id: messageId }),
  );
}

function normalizeForMatch(value: string): string {
  return value.trim().toLowerCase();
}

function resolveMailAccountName(configuredAccount: string, discoveredAccounts: DiscoveredMailAccount[]): DiscoveredMailAccount {
  const normalized = normalizeForMatch(configuredAccount);

  const exactName = discoveredAccounts.find((account) => normalizeForMatch(account.name) === normalized);
  if (exactName) {
    return exactName;
  }

  const exactEmail = discoveredAccounts.find((account) =>
    account.emails.some((email) => normalizeForMatch(email) === normalized),
  );
  if (exactEmail) {
    return exactEmail;
  }

  const partialEmail = discoveredAccounts.find((account) =>
    account.emails.some((email) => normalizeForMatch(email).includes(normalized)),
  );
  if (partialEmail) {
    return partialEmail;
  }

  throw new Error(
    `[MailSource] Could not resolve configured account "${configuredAccount}" against discovered Apple Mail accounts.`,
  );
}

function selectSentMailbox(actualAccountName: string, mailboxInventory: MailboxInventoryRecord[]): string | null {
  const candidates = mailboxInventory.filter((mailbox) => mailbox.account === actualAccountName);
  const preferred = ["Sent Mail", "Sent Messages"];

  for (const exact of preferred) {
    const match = candidates.find((candidate) => candidate.name === exact);
    if (match) {
      return match.name;
    }
  }

  const fuzzy = candidates.find((candidate) => /sent/i.test(candidate.name));
  return fuzzy?.name ?? null;
}

export function resolveConfiguredMailAccounts(
  configAccounts: MailIntelligenceAccount[],
  discoveredAccounts: DiscoveredMailAccount[],
  mailboxInventory: MailboxInventoryRecord[],
): ResolvedMailAccount[] {
  return configAccounts.map((account) => {
    const resolved = resolveMailAccountName(account.account, discoveredAccounts);
    return {
      configuredAccount: account.account,
      actualAccountName: resolved.name,
      emails: [...resolved.emails],
      mailbox: account.mailbox,
      sentMailbox: selectSentMailbox(resolved.name, mailboxInventory),
      personaId: account.personaId,
      persona: account.persona,
      role: account.role,
      summary: account.summary,
      primaryReplyFrom: account.primaryReplyFrom,
      catchAll: account.catchAll,
      defaultLane: account.defaultLane,
      sourceRules: account.sourceRules,
    };
  });
}

function matchSourceRules(message: { subject: string; sender: string; content: string }, account: ResolvedMailAccount): MailIntelligenceSourceRule[] {
  const haystack = `${message.subject}\n${message.sender}\n${message.content}`.toLowerCase();
  return account.sourceRules.filter((rule) => rule.matches.some((term) => haystack.includes(term.toLowerCase())));
}

async function harvestMailbox(
  session: ToolCaller,
  account: ResolvedMailAccount,
  mailbox: string,
  direction: "inbound" | "outbound",
  limit: number,
  errors: string[],
): Promise<HarvestedMailMessage[]> {
  const summaries = await listMailboxMessages(session, mailbox, account.actualAccountName, limit);

  return Promise.all(
    summaries.map(async (summary) => {
      try {
        const detail = await getMailboxMessage(session, mailbox, account.actualAccountName, summary.id);
        return {
          ...detail,
          configuredAccount: account.configuredAccount,
          actualAccountName: account.actualAccountName,
          accountEmails: [...account.emails],
          mailbox,
          personaId: account.personaId,
          persona: account.persona,
          role: account.role,
          summary: account.summary,
          defaultLane: account.defaultLane,
          primaryReplyFrom: account.primaryReplyFrom,
          catchAll: account.catchAll,
          direction,
          matchedRules: matchSourceRules(detail, account),
        } satisfies HarvestedMailMessage;
      } catch (error) {
        errors.push(
          `[MailSource] Failed to fetch message ${summary.id} from ${account.actualAccountName}/${mailbox}: ${(error as Error).message}`,
        );
        return {
          ...summary,
          content: "",
          toRecipients: [],
          ccRecipients: [],
          configuredAccount: account.configuredAccount,
          actualAccountName: account.actualAccountName,
          accountEmails: [...account.emails],
          mailbox,
          personaId: account.personaId,
          persona: account.persona,
          role: account.role,
          summary: account.summary,
          defaultLane: account.defaultLane,
          primaryReplyFrom: account.primaryReplyFrom,
          catchAll: account.catchAll,
          direction,
          matchedRules: matchSourceRules({ ...summary, content: "" }, account),
        } satisfies HarvestedMailMessage;
      }
    }),
  );
}

export async function harvestMailFromSessions(
  bootstrap: CorpusBootstrapSnapshot,
  sessions: { appleMail: McpSession; mailIntelligence: McpSession },
  options: Omit<HarvestMailOptions, "bootstrap" | "env"> = {},
): Promise<MailHarvestResult> {
  const inboxLimit = options.inboxLimit ?? 5;
  const sentLimit = options.sentLimit ?? 3;
  const includeSent = options.includeSent ?? true;
  const errors: string[] = [];

  const [discoveredAccounts, mailboxInventory] = await Promise.all([
    loadDiscoveredMailAccounts(sessions.mailIntelligence),
    loadMailboxInventory(sessions.appleMail),
  ]);

  const resolvedAccounts = resolveConfiguredMailAccounts(
    bootstrap.mailIntelligenceConfig.accounts,
    discoveredAccounts,
    mailboxInventory,
  );

  const accounts: MailHarvestAccountResult[] = [];

  for (const account of resolvedAccounts) {
    let inboxMessages: HarvestedMailMessage[] = [];
    let sentMessages: HarvestedMailMessage[] = [];

    try {
      inboxMessages = await harvestMailbox(
        sessions.appleMail,
        account,
        account.mailbox,
        "inbound",
        inboxLimit,
        errors,
      );
    } catch (error) {
      errors.push(
        `[MailSource] Failed to harvest inbox for ${account.configuredAccount}: ${(error as Error).message}`,
      );
    }

    if (includeSent && account.sentMailbox) {
      try {
        sentMessages = await harvestMailbox(
          sessions.appleMail,
          account,
          account.sentMailbox,
          "outbound",
          sentLimit,
          errors,
        );
      } catch (error) {
        errors.push(
          `[MailSource] Failed to harvest sent mailbox for ${account.configuredAccount}: ${(error as Error).message}`,
        );
      }
    }

    accounts.push({ account, inboxMessages, sentMessages });
  }

  return {
    capturedAt: new Date().toISOString(),
    bootstrap,
    discoveredAccounts,
    mailboxInventory,
    accounts,
    errors,
  };
}

export async function harvestMail(repoRoot: string, options: HarvestMailOptions = {}): Promise<MailHarvestResult> {
  const bootstrap = options.bootstrap ?? (await bootstrapCorpusContext(repoRoot, options.env));
  const appleMail = await connectToServer("apple-mail", repoRoot, options.env);
  const mailIntelligence = await connectToServer("mail-intelligence", repoRoot, options.env);

  try {
    return await harvestMailFromSessions(
      bootstrap,
      { appleMail, mailIntelligence },
      {
        inboxLimit: options.inboxLimit,
        sentLimit: options.sentLimit,
        includeSent: options.includeSent,
      },
    );
  } finally {
    await Promise.allSettled([appleMail.close(), mailIntelligence.close()]);
  }
}
