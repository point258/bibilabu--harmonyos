/**
 * BasicDataSource.ets — LazyForEach 数据源
 * 三条约定：
 *   - 变更精确派发，绝不整页 notifyDataReload（除非真重载）；
 *   - getData 越界返回最后一项，防懒加载竞态白屏；
 *   - appendData 逐条 onDataAdd，保住滚动位置。
 *
 * 监听器类型用 ArkUI 内置的 DataChangeListener。
 * 注意名字：不是 IDataChangeListener、也不是 IDataSourceListener ——
 *    写错会报 "Cannot find name 'IDataChangeListener'. Did you mean 'DataChangeListener'?"。
 * 另外 forEach 的回调要写成块语句，箭头函数直接返回表达式会触发
 * arkts-no-implicit-return-types。
 */

export class BasicDataSource<T> implements IDataSource {
  private listeners: DataChangeListener[] = [];
  protected data: T[] = [];

  totalCount(): number {
    return this.data.length;
  }

  getData(index: number): T {
    if (index < 0 || index >= this.data.length) {
      return this.data[this.data.length - 1];
    }
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  protected notifyReload(): void {
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataReloaded();
    });
  }

  protected notifyAdd(index: number): void {
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataAdd(index);
    });
  }

  protected notifyChange(index: number): void {
    this.listeners.forEach((l: DataChangeListener) => {
      l.onDataChange(index);
    });
  }

  /** 增量追加：逐条 onDataAdd */
  appendData(items: T[]): void {
    const start: number = this.data.length;
    this.data.push(...items);
    for (let i = 0; i < items.length; i++) {
      this.notifyAdd(start + i);
    }
  }

  /** 整体替换（下拉刷新/换条件时用，会回到列表顶部） */
  replaceData(items: T[]): void {
    this.data = items;
    this.notifyReload();
  }

  /** 去重合并：仅追加未见过的 key */
  appendUnique(items: T[], keyOf: (item: T) => string): void {
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < this.data.length; i++) {
      seen.add(keyOf(this.data[i]));
    }
    const fresh: T[] = items.filter((it: T) => !seen.has(keyOf(it)));
    this.appendData(fresh);
  }

  changeAt(index: number): void {
    this.notifyChange(index);
  }

  /**
   * 就地替换某一项并精确派发。
   *
   * 必须经由本方法写数据源本体：`snapshot()` 是 `slice()` 出来的**副本**，
   *    拿到副本后 `arr[i] = xxx` 只改了那个临时数组，`this.data` 纹丝不动，
   *    再 `changeAt(i)` 也只会让列表重新读到旧值 —— 表现就是"数据明明取到了，界面永远是空"。
   */
  updateAt(index: number, item: T): void {
    if (index < 0 || index >= this.data.length) {
      return;
    }
    this.data[index] = item;
    this.notifyChange(index);
  }

  clear(): void {
    this.data = [];
    this.notifyReload();
  }

  snapshot(): T[] {
    return this.data.slice();
  }
}
