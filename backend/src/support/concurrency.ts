// AI呼び出しの同時実行数を制限する。上限を超えたら待たせずに断る (=フォールバックへ)。
export class ConcurrencyGate {
  readonly #max: number;
  #active = 0;

  constructor(max: number) {
    this.#max = max;
  }

  get active(): number {
    return this.#active;
  }

  /** 取得できたら解放関数を返す。解放は何度呼んでも1回分だけ */
  tryAcquire(): (() => void) | null {
    if (this.#active >= this.#max) return null;
    this.#active += 1;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.#active -= 1;
    };
  }
}
