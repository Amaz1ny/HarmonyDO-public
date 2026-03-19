import { SmartAvatar } from './SmartAvatar';

export class PostShareImageParams {
  topicTitle: string = '';
  authorName: string = '';
  username: string = '';
  avatarUrl: string = '';
  timeText: string = '';
  floorText: string = '';
  contentText: string = '';
  shareUrl: string = '';

  constructor() {
  }
}

class ShareImageTheme {
  bgColor: string = '#FFFFFF';
  primaryText: string = '#111111';
  secondaryText: string = '#666666';
  contentBg: string = '#FFFFFF';
  contentText: string = '#111111';
  linkText: string = '#666666';

  constructor() {
  }
}

function resolveTheme(themeIndex: number): ShareImageTheme {
  const idx: number = Math.round(themeIndex);
  const t: ShareImageTheme = new ShareImageTheme();
  switch (idx) {
    // 经典（米色）
    case 0:
      t.bgColor = '#F3EBDD';
      t.primaryText = '#1F2328';
      t.secondaryText = '#6B7280';
      t.contentBg = '#FFFFFF';
      t.contentText = '#1F2328';
      t.linkText = '#6B7280';
      return t;
    // 纯白
    case 1:
      t.bgColor = '#FFFFFF';
      t.primaryText = '#1F2328';
      t.secondaryText = '#6B7280';
      t.contentBg = '#F4F6F8';
      t.contentText = '#1F2328';
      t.linkText = '#6B7280';
      return t;
    // 深色
    case 2:
      t.bgColor = '#1C1C1E';
      t.primaryText = '#FFFFFF';
      t.secondaryText = '#B0B3B8';
      t.contentBg = '#2C2C2E';
      t.contentText = '#FFFFFF';
      t.linkText = '#B0B3B8';
      return t;
    // 纯黑
    case 3:
      t.bgColor = '#000000';
      t.primaryText = '#FFFFFF';
      t.secondaryText = '#C6C6C6';
      t.contentBg = '#1A1A1A';
      t.contentText = '#FFFFFF';
      t.linkText = '#C6C6C6';
      return t;
    // 蓝调
    case 4:
      t.bgColor = '#D9E8FF';
      t.primaryText = '#1F2328';
      t.secondaryText = '#6B7280';
      t.contentBg = '#FFFFFF';
      t.contentText = '#1F2328';
      t.linkText = '#4B5563';
      return t;
    // 绿野
    case 5:
      t.bgColor = '#DDF3E2';
      t.primaryText = '#1F2328';
      t.secondaryText = '#6B7280';
      t.contentBg = '#FFFFFF';
      t.contentText = '#1F2328';
      t.linkText = '#4B5563';
      return t;
    default:
      return resolveTheme(0);
  }
}

@Builder
function BrandLogo() {
  // 用基础图形近似绘制 FluxDO 的 LINUX DO 圆形条纹 Logo
  Stack() {
    Circle()
      .width(24)
      .height(24)
      .fill(Color.White)

    Column() {
      Rect().width(24).height(8).fill('#111111')
      Rect().width(24).height(8).fill('#FFFFFF')
      Rect().width(24).height(8).fill('#F59E0B')
    }
    .width(24)
    .height(24)
    .borderRadius(12)
    .clip(true)
  }
  .width(24)
  .height(24)
}

@Builder
export function postShareImageBuilder(params: PostShareImageParams, themeIndex: number = 0) {
  Column() {
    // 顶部品牌
    Row() {
      Column() {
        BrandLogo()
      }
      .margin({ right: 10 })

      Text('LINUX DO')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(resolveTheme(themeIndex).primaryText)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    // 话题标题（最多 2 行）
    Text(params.topicTitle)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(resolveTheme(themeIndex).primaryText)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .margin({ top: 10 })

    // 作者信息
    Row() {
      SmartAvatar({
        avatarUrl: params.avatarUrl,
        avatarSize: 36,
        fallbackText: params.username,
        bgColor: '#E8EAF0'
      })

      Column() {
        Text(params.authorName.length > 0 ? params.authorName : params.username)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(resolveTheme(themeIndex).primaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(`@${params.username}`)
            .fontSize(11)
            .fontColor(resolveTheme(themeIndex).secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(' · ')
            .fontSize(11)
            .fontColor(resolveTheme(themeIndex).secondaryText)
          Text(params.timeText)
            .fontSize(11)
            .fontColor(resolveTheme(themeIndex).secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 10 })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text(params.floorText)
          .fontSize(10)
          .fontColor(resolveTheme(themeIndex).secondaryText)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12 })

    // 正文（纯文本）
    Column() {
      Text(params.contentText)
        .fontSize(15)
        .fontColor(resolveTheme(themeIndex).contentText)
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(resolveTheme(themeIndex).contentBg)
    .borderRadius(12)
    .margin({ top: 14 })

    // 底部链接行
    Row() {
      SymbolGlyph($r('sys.symbol.link'))
        .fontSize(14)
        .fontColor([resolveTheme(themeIndex).linkText])
        .margin({ right: 6 })
      Text(params.shareUrl)
        .fontSize(11)
        .fontColor(resolveTheme(themeIndex).linkText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12 })
  }
  .width('100%')
  .padding(16)
  .backgroundColor(resolveTheme(themeIndex).bgColor)
  .borderRadius(16)
}

