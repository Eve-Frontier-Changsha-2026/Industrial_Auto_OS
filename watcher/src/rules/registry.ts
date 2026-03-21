import type { RuleHandler } from "./interface.js";

export class RuleRegistry {
  private handlers: RuleHandler[] = [];

  register(handler: RuleHandler): void {
    this.handlers.push(handler);
  }

  getByEventType(type: string): RuleHandler[] {
    return this.handlers.filter(
      (h) => h.enabled && h.eventType && type.endsWith(h.eventType),
    );
  }

  getByScheduleType(type: string): RuleHandler[] {
    return this.handlers.filter(
      (h) => h.enabled && h.scheduleType === type,
    );
  }

  listAll(): RuleHandler[] {
    return [...this.handlers];
  }
}
