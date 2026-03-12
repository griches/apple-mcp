import fs from "node:fs";
import path from "node:path";
import {
  getCorpusOverview,
  getMailIntelligenceConfig,
  getObjectSection,
  type JsonObject,
  type JsonValue,
} from "./corpus.js";

interface LaravelTableBlueprint {
  table: string;
  columns: Array<{ name: string; type: string; nullable?: boolean; unique?: boolean }>;
}

function isRecord(value: JsonValue | undefined): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asObject(value: JsonValue | undefined, label: string): JsonObject {
  if (!isRecord(value)) {
    throw new Error(`${label} must be an object.`);
  }
  return value;
}

function asArray(value: JsonValue | undefined, label: string): JsonValue[] {
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array.`);
  }
  return value;
}

function jsonToPhp(value: JsonValue, indent = 0): string {
  const space = " ".repeat(indent);
  const next = indent + 4;

  if (value === null) {
    return "null";
  }

  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }

  if (typeof value === "number") {
    return String(value);
  }

  if (typeof value === "string") {
    return `'${value.replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
  }

  if (Array.isArray(value)) {
    if (!value.length) {
      return "[]";
    }

    const items = value
      .map((item) => `${" ".repeat(next)}${jsonToPhp(item, next)},`)
      .join("\n");
    return `[\n${items}\n${space}]`;
  }

  const entries = Object.entries(value);
  if (!entries.length) {
    return "[]";
  }

  const lines = entries
    .map(([key, child]) => `${" ".repeat(next)}'${key}' => ${jsonToPhp(child, next)},`)
    .join("\n");
  return `[\n${lines}\n${space}]`;
}

function getPersonaSeedData(): JsonObject[] {
  const mailConfig = getMailIntelligenceConfig();
  const accounts = asArray(mailConfig.accounts, "mail_intelligence.accounts");
  return accounts.map((accountValue) => {
    const account = asObject(accountValue, "mail_intelligence.accounts[]");
    const sourceRules = Array.isArray(account.sourceRules) ? account.sourceRules.length : 0;
    return {
      persona_id: account.personaId ?? null,
      account: account.account ?? null,
      mailbox: account.mailbox ?? null,
      persona: account.persona ?? null,
      role: account.role ?? null,
      summary: account.summary ?? null,
      primary_reply_from: account.primaryReplyFrom ?? false,
      catch_all: account.catchAll ?? false,
      default_lane: account.defaultLane ?? null,
      metadata: {
        source_rule_count: sourceRules,
      },
    };
  });
}

function getDomainSeedData(): JsonObject[] {
  const mailConfig = getMailIntelligenceConfig();
  const domains = asArray(mailConfig.domains, "mail_intelligence.domains");
  return domains.map((domainValue) => {
    const domain = asObject(domainValue, "mail_intelligence.domains[]");
    return {
      name: domain.name ?? null,
      matches: domain.matches ?? [],
    };
  });
}

function getSourceRuleSeedData(): JsonObject[] {
  const mailConfig = getMailIntelligenceConfig();
  const accounts = asArray(mailConfig.accounts, "mail_intelligence.accounts");
  return accounts.flatMap((accountValue) => {
    const account = asObject(accountValue, "mail_intelligence.accounts[]");
    const rules = Array.isArray(account.sourceRules) ? account.sourceRules : [];
    return rules.map((ruleValue) => {
      const rule = asObject(ruleValue as JsonObject, "mail_intelligence.accounts[].sourceRules[]");
      return {
        persona_id: account.personaId ?? null,
        label: rule.label ?? null,
        matches: rule.matches ?? [],
        domain: rule.domain ?? null,
        lane: rule.lane ?? null,
        priority: rule.priority ?? "normal",
      };
    });
  });
}

function getOutputTargetSeedData(): JsonObject[] {
  const outputTargets = getObjectSection("output_targets");
  const targets = asArray(outputTargets.targets, "output_targets.targets");
  return targets.map((targetValue) => {
    const target = asObject(targetValue, "output_targets.targets[]");
    return {
      name: target.name ?? null,
      type: target.type ?? null,
      destination: target.destination ?? null,
      role: target.role ?? null,
      settings: {},
    };
  });
}

function getTableBlueprints(): LaravelTableBlueprint[] {
  return [
    {
      table: "brain_personas",
      columns: [
        { name: "id", type: "id" },
        { name: "persona_id", type: "string", unique: true },
        { name: "account", type: "string" },
        { name: "mailbox", type: "string" },
        { name: "persona", type: "string" },
        { name: "role", type: "string" },
        { name: "summary", type: "text", nullable: true },
        { name: "primary_reply_from", type: "boolean" },
        { name: "catch_all", type: "boolean" },
        { name: "default_lane", type: "string" },
        { name: "metadata", type: "json", nullable: true }
      ]
    },
    {
      table: "brain_domains",
      columns: [
        { name: "id", type: "id" },
        { name: "name", type: "string", unique: true },
        { name: "matches", type: "json" }
      ]
    },
    {
      table: "brain_source_rules",
      columns: [
        { name: "id", type: "id" },
        { name: "persona_id", type: "string" },
        { name: "label", type: "string" },
        { name: "matches", type: "json" },
        { name: "domain", type: "string" },
        { name: "lane", type: "string" },
        { name: "priority", type: "string" }
      ]
    },
    {
      table: "brain_output_targets",
      columns: [
        { name: "id", type: "id" },
        { name: "name", type: "string", unique: true },
        { name: "type", type: "string" },
        { name: "destination", type: "string" },
        { name: "role", type: "string" },
        { name: "settings", type: "json", nullable: true }
      ]
    }
  ];
}

export function getLaravelBrainBlueprint(): JsonObject {
  const schema = getObjectSection("schema");
  const profile = getObjectSection("canonical_profile");
  const laravel = getObjectSection("laravel_application");

  return {
    corpus: getCorpusOverview(),
    config_namespace: laravel.config_namespace ?? "brain",
    package_name: schema.name ?? null,
    application_role: profile.primary_application_layer ?? null,
    tables: getTableBlueprints() as unknown as JsonValue,
    seed_data: {
      personas: getPersonaSeedData(),
      domains: getDomainSeedData(),
      source_rules: getSourceRuleSeedData(),
      output_targets: getOutputTargetSeedData(),
    },
    routes: laravel.suggested_routes ?? [],
    models: laravel.suggested_models ?? [],
  };
}

function renderMigration(): string {
  return `<?php

use Illuminate\\Database\\Migrations\\Migration;
use Illuminate\\Database\\Schema\\Blueprint;
use Illuminate\\Support\\Facades\\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('brain_personas', function (Blueprint $table): void {
            $table->id();
            $table->string('persona_id')->unique();
            $table->string('account');
            $table->string('mailbox');
            $table->string('persona');
            $table->string('role');
            $table->text('summary')->nullable();
            $table->boolean('primary_reply_from')->default(false);
            $table->boolean('catch_all')->default(false);
            $table->string('default_lane');
            $table->json('metadata')->nullable();
            $table->timestamps();
        });

        Schema::create('brain_domains', function (Blueprint $table): void {
            $table->id();
            $table->string('name')->unique();
            $table->json('matches');
            $table->timestamps();
        });

        Schema::create('brain_source_rules', function (Blueprint $table): void {
            $table->id();
            $table->string('persona_id');
            $table->string('label');
            $table->json('matches');
            $table->string('domain');
            $table->string('lane');
            $table->string('priority')->default('normal');
            $table->timestamps();
        });

        Schema::create('brain_output_targets', function (Blueprint $table): void {
            $table->id();
            $table->string('name')->unique();
            $table->string('type');
            $table->string('destination');
            $table->string('role');
            $table->json('settings')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('brain_output_targets');
        Schema::dropIfExists('brain_source_rules');
        Schema::dropIfExists('brain_domains');
        Schema::dropIfExists('brain_personas');
    }
};
`;
}

function renderSeeder(): string {
  const blueprint = getLaravelBrainBlueprint();
  const seedData = asObject(blueprint.seed_data, "seed_data");

  return `<?php

namespace Database\\Seeders;

use Illuminate\\Database\\Seeder;
use Illuminate\\Support\\Facades\\DB;

class BrainSeeder extends Seeder
{
    public function run(): void
    {
        DB::table('brain_personas')->truncate();
        DB::table('brain_domains')->truncate();
        DB::table('brain_source_rules')->truncate();
        DB::table('brain_output_targets')->truncate();

        DB::table('brain_personas')->insert(${jsonToPhp(seedData.personas ?? [], 8)});
        DB::table('brain_domains')->insert(${jsonToPhp(seedData.domains ?? [], 8)});
        DB::table('brain_source_rules')->insert(${jsonToPhp(seedData.source_rules ?? [], 8)});
        DB::table('brain_output_targets')->insert(${jsonToPhp(seedData.output_targets ?? [], 8)});
    }
}
`;
}

function renderConfig(): string {
  const blueprint = getLaravelBrainBlueprint();
  return `<?php

return ${jsonToPhp(blueprint, 0)};
`;
}

function renderController(): string {
  return `<?php

namespace App\\Http\\Controllers;

use Illuminate\\Http\\JsonResponse;
use Illuminate\\Support\\Facades\\Config;
use Illuminate\\Support\\Facades\\DB;

class BrainController extends Controller
{
    public function overview(): JsonResponse
    {
        return response()->json(Config::get('brain'));
    }

    public function personas(): JsonResponse
    {
        return response()->json(DB::table('brain_personas')->orderBy('persona')->get());
    }

    public function domains(): JsonResponse
    {
        return response()->json(DB::table('brain_domains')->orderBy('name')->get());
    }

    public function sourceRules(): JsonResponse
    {
        return response()->json(DB::table('brain_source_rules')->orderBy('persona_id')->orderBy('label')->get());
    }

    public function outputTargets(): JsonResponse
    {
        return response()->json(DB::table('brain_output_targets')->orderBy('name')->get());
    }
}
`;
}

function renderRoutes(): string {
  return `<?php

use App\\Http\\Controllers\\BrainController;
use Illuminate\\Support\\Facades\\Route;

Route::prefix('brain')->group(function (): void {
    Route::get('overview', [BrainController::class, 'overview']);
    Route::get('personas', [BrainController::class, 'personas']);
    Route::get('domains', [BrainController::class, 'domains']);
    Route::get('source-rules', [BrainController::class, 'sourceRules']);
    Route::get('output-targets', [BrainController::class, 'outputTargets']);
});
`;
}

function writeFile(targetPath: string, contents: string): void {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, contents, "utf8");
}

export function exportLaravelBrainPack(targetDir: string): JsonObject {
  const resolvedTarget = path.resolve(targetDir);
  const writtenFiles = [
    path.join(resolvedTarget, "config", "brain.php"),
    path.join(resolvedTarget, "database", "migrations", "2026_03_12_000000_create_brain_tables.php"),
    path.join(resolvedTarget, "database", "seeders", "BrainSeeder.php"),
    path.join(resolvedTarget, "app", "Http", "Controllers", "BrainController.php"),
    path.join(resolvedTarget, "routes", "brain.php"),
  ];

  writeFile(writtenFiles[0], renderConfig());
  writeFile(writtenFiles[1], renderMigration());
  writeFile(writtenFiles[2], renderSeeder());
  writeFile(writtenFiles[3], renderController());
  writeFile(writtenFiles[4], renderRoutes());

  return {
    target_dir: resolvedTarget,
    written_files: writtenFiles,
  };
}
