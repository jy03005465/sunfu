class LegalSection {
  const LegalSection({
    required this.title,
    required this.body,
    this.bullets = const [],
  });

  final String title;
  final String body;
  final List<String> bullets;
}

class LegalDocumentContent {
  const LegalDocumentContent({
    required this.title,
    required this.summary,
    required this.sections,
    required this.footer,
  });

  final String title;
  final String summary;
  final List<LegalSection> sections;
  final String footer;
}

class LegalDocuments {
  static const String privacyConsentVersion = '2026-04-13';

  static const LegalDocumentContent privacyPolicy = LegalDocumentContent(
    title: '隐私政策',
    summary: '2048 Solo 是一款离线单机益智游戏。当前版本不会要求你注册账号，也不会向开发者自建服务器上传你的游戏数据。',
    sections: [
      LegalSection(
        title: '我们会处理哪些信息',
        body: '当前版本主要在设备本地保存与你的游戏体验直接相关的数据。',
        bullets: ['当前游戏进度与最高分', '音效、震动等设置状态', '新手引导显示状态', '本地统计与成就进度'],
      ),
      LegalSection(
        title: '这些信息如何被使用',
        body: '这些本地数据仅用于提供游戏功能本身，不会被用于画像、广告定向或社交关系分析。',
        bullets: ['恢复上次游戏进度', '记录最佳成绩与展示成长数据', '保存你的个性化设置'],
      ),
      LegalSection(
        title: '网络与第三方服务',
        body:
            '当前版本定位为离线单机游戏，不需要登录，不强制联网，也不依赖开发者自建服务器提供核心功能。若未来接入广告、内购、统计或崩溃分析，我们会在正式上架版本中更新对应说明。',
      ),
      LegalSection(
        title: '你的权利',
        body: '你可以通过应用内设置清除本地进度和部分记录。正式上架前，我们会补充开发者名称、联系邮箱与线上隐私政策链接。',
      ),
    ],
    footer: '正式发布前，请将本页内容与商店页隐私政策、实际 SDK、权限申请情况保持一致。',
  );

  static const LegalDocumentContent userAgreement = LegalDocumentContent(
    title: '用户协议',
    summary: '在使用 2048 Solo 前，请确认你已经阅读并同意本协议的核心内容。',
    sections: [
      LegalSection(
        title: '服务内容',
        body:
            '2048 Solo 向你提供离线数字合成玩法、本地存档、成就统计、设置管理等功能。应用当前不提供账号、社交、联机或云端存档服务。',
      ),
      LegalSection(
        title: '使用规则',
        body: '你应以合法、正常的方式使用本应用，不得利用本应用从事违法违规活动。',
        bullets: [
          '不得逆向破坏、恶意篡改或传播非法修改版本',
          '不得冒用开发者身份或伪造应用内容',
          '不得利用应用页面、素材或文案从事违法用途',
        ],
      ),
      LegalSection(
        title: '知识产权',
        body: '应用中的代码、界面、图标、品牌文案及相关素材由开发者或合法授权方享有相应权利。未经许可，不得用于商业复制、转售或再分发。',
      ),
      LegalSection(
        title: '责任说明',
        body:
            '本应用以当前版本形态向你提供服务。我们会持续优化体验，但不对因设备环境、系统限制、非官方修改版本或不可抗力导致的问题承担超出法律规定的责任。',
      ),
      LegalSection(
        title: '协议更新',
        body: '如果应用接入广告、内购、联网服务或其他新增能力，我们可能更新本协议与隐私政策，并通过应用内或商店页面进行说明。',
      ),
    ],
    footer: '正式上架前，请补充开发者主体、联系方式、用户申诉渠道与正式协议链接。',
  );
}
