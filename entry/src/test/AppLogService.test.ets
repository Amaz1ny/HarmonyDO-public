import { describe, it, expect } from '@ohos/hypium';
import {
  AppLogService,
  AppLogEntry,
  AppLogFileAdapter,
  AppLogLevel,
  AppLogType
} from '../main/ets/common/utils/AppLogService';
import { filterEntries } from '../main/ets/views/pages/AppLogsPage';

class MemoryLogFileAdapter implements AppLogFileAdapter {
  content: string = '';

  readText(): string {
    return this.content;
  }

  writeText(text: string): void {
    this.content = text;
  }

  clear(): void {
    this.content = '';
  }
}

function makeEntry(message: string, level: AppLogLevel = 'info', type: AppLogType = 'general'): AppLogEntry {
  return {
    timestamp: '2026-03-27T10:00:00.000Z',
    level,
    type,
    message,
    tag: 'test'
  };
}

export default function appLogServiceTest() {
  describe('appLogServiceTest', () => {
    it('writes entries and reads them in desc order', 0, () => {
      const fs: MemoryLogFileAdapter = new MemoryLogFileAdapter();
      const service: AppLogService = new AppLogService(fs, 4096);

      service.write(makeEntry('first'));
      service.write(makeEntry('second'));

      const rows: AppLogEntry[] = service.readEntries();
      expect(rows.length).assertEqual(2);
      expect(rows[0].message).assertEqual('second');
      expect(rows[1].message).assertEqual('first');
    });

    it('skips malformed json lines', 0, () => {
      const fs: MemoryLogFileAdapter = new MemoryLogFileAdapter();
      fs.content =
        '{"timestamp":"2026-03-27T10:00:00.000Z","level":"info","type":"general","message":"ok"}\nnot-json\n{"timestamp":"2026-03-27T10:00:01.000Z","level":"error","type":"lifecycle","message":"bad"}';
      const service: AppLogService = new AppLogService(fs, 4096);

      const rows: AppLogEntry[] = service.readEntries();
      expect(rows.length).assertEqual(2);
      expect(rows[0].message).assertEqual('bad');
      expect(rows[1].message).assertEqual('ok');
    });

    it('clears all entries', 0, () => {
      const fs: MemoryLogFileAdapter = new MemoryLogFileAdapter();
      const service: AppLogService = new AppLogService(fs, 4096);
      service.write(makeEntry('x'));
      service.clear();
      expect(service.readEntries().length).assertEqual(0);
    });

    it('trims oldest content when over max bytes', 0, () => {
      const fs: MemoryLogFileAdapter = new MemoryLogFileAdapter();
      const service: AppLogService = new AppLogService(fs, 160);

      service.write(makeEntry('11111111111111111111'));
      service.write(makeEntry('22222222222222222222'));
      service.write(makeEntry('33333333333333333333'));

      const rows: AppLogEntry[] = service.readEntries();
      expect(rows.length > 0).assertEqual(true);
      expect(rows[0].message).assertEqual('33333333333333333333');
    });

    it('provides level helpers', 0, () => {
      const fs: MemoryLogFileAdapter = new MemoryLogFileAdapter();
      const service: AppLogService = new AppLogService(fs, 4096);
      service.info('lifecycle', 'create', 'EntryAbility');
      service.warning('general', 'warn-sample', 'Index');
      service.error('general', 'error-sample', 'Profile');

      const rows: AppLogEntry[] = service.readEntries();
      expect(rows.length).assertEqual(3);
      expect(rows[0].level).assertEqual('error');
      expect(rows[1].level).assertEqual('warning');
      expect(rows[2].level).assertEqual('info');
    });

    it('filters entries by mode', 0, () => {
      const list: AppLogEntry[] = [
        { timestamp: '1', level: 'info', type: 'general', message: 'a' },
        { timestamp: '2', level: 'error', type: 'lifecycle', message: 'b' }
      ];
      expect(filterEntries(list, 'all').length).assertEqual(2);
      expect(filterEntries(list, 'error').length).assertEqual(1);
      expect(filterEntries(list, 'lifecycle').length).assertEqual(1);
      expect(filterEntries(list, 'general').length).assertEqual(1);
    });
  });
}
