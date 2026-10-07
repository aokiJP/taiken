// CLIENT_TOKENS 用のランダムなトークンを生成する (npm run token)
import { randomBytes } from 'node:crypto';

process.stdout.write(`${randomBytes(32).toString('base64url')}\n`);
