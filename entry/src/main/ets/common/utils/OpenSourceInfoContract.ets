export enum OpenSourceItemActionType {
  None = 'none',
  External = 'external'
}

export interface OpenSourceInfoItem {
  title: string;
  subtitle: string;
  actionType: OpenSourceItemActionType;
  url: string;
}

export interface OpenSourceInfoSection {
  title: string;
  items: OpenSourceInfoItem[];
}

export function buildOpenSourceSections(): OpenSourceInfoSection[] {
  return [
    {
      title: '项目说明',
      items: [
        {
          title: 'LDO社区',
          subtitle: 'Linux.do 的鸿蒙原生社区客户端',
          actionType: OpenSourceItemActionType.None,
          url: ''
        },
        {
          title: '致谢',
          subtitle: '灵感来自 FluxDO，感谢 Linux.do 社区与开源作者',
          actionType: OpenSourceItemActionType.None,
          url: ''
        }
      ]
    },
    {
      title: '开源合规',
      items: [
        {
          title: '开源协议',
          subtitle: 'GPL-3.0（详见仓库 LICENSE）',
          actionType: OpenSourceItemActionType.None,
          url: ''
        },
        {
          title: '免责声明',
          subtitle: '本项目为非官方客户端，与 Linux.do 官方无直接关联',
          actionType: OpenSourceItemActionType.None,
          url: ''
        }
      ]
    }
  ];
}
