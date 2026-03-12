#!/usr/bin/env node
import path from "node:path";
import { exportLaravelBrainPack } from "./laravel.js";

const targetDir = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.resolve(process.cwd(), "laravel-brain-pack");

const result = exportLaravelBrainPack(targetDir);
console.log(JSON.stringify(result, null, 2));
