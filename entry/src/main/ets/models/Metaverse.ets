export class OAuthAuthorizationContext {
  serviceKey: string = '';
  serviceName: string = '';
  approveUrl: string = '';
}

export class LdcUserInfo {
  id: number = 0;
  username: string = '';
  nickname: string = '';
  trustLevel: number = 0;
  avatarUrl: string = '';
  totalReceive: string = '0';
  totalPayment: string = '0';
  totalTransfer: string = '0';
  totalCommunity: string = '0';
  communityBalance: string = '0';
  availableBalance: string = '0';
  payScore: number = 0;
  isPayKey: boolean = false;
  isAdmin: boolean = false;
  remainQuota: string = '0';
  payLevel: number = 0;
  dailyLimit: number = 0;

  static fromJson(json: Record<string, Object>): LdcUserInfo {
    const info: LdcUserInfo = new LdcUserInfo();
    const idVal = json['id'];
    const usernameVal = json['username'];
    const nicknameVal = json['nickname'];
    const trustLevelVal = json['trust_level'];
    const avatarUrlVal = json['avatar_url'];
    const totalReceiveVal = json['total_receive'];
    const totalPaymentVal = json['total_payment'];
    const totalTransferVal = json['total_transfer'];
    const totalCommunityVal = json['total_community'];
    const communityBalanceVal = json['community_balance'];
    const availableBalanceVal = json['available_balance'];
    const payScoreVal = json['pay_score'];
    const isPayKeyVal = json['is_pay_key'];
    const isAdminVal = json['is_admin'];
    const remainQuotaVal = json['remain_quota'];
    const payLevelVal = json['pay_level'];
    const dailyLimitVal = json['daily_limit'];

    info.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    info.username = usernameVal !== undefined && usernameVal !== null ? usernameVal.toString() : '';
    info.nickname = nicknameVal !== undefined && nicknameVal !== null ? nicknameVal.toString() : '';
    info.trustLevel = trustLevelVal !== undefined && trustLevelVal !== null ? Number(trustLevelVal.toString()) : 0;
    info.avatarUrl = avatarUrlVal !== undefined && avatarUrlVal !== null ? avatarUrlVal.toString() : '';
    info.totalReceive = totalReceiveVal !== undefined && totalReceiveVal !== null ? totalReceiveVal.toString() : '0';
    info.totalPayment = totalPaymentVal !== undefined && totalPaymentVal !== null ? totalPaymentVal.toString() : '0';
    info.totalTransfer = totalTransferVal !== undefined && totalTransferVal !== null ? totalTransferVal.toString() : '0';
    info.totalCommunity = totalCommunityVal !== undefined && totalCommunityVal !== null
      ? totalCommunityVal.toString()
      : '0';
    info.communityBalance = communityBalanceVal !== undefined && communityBalanceVal !== null
      ? communityBalanceVal.toString()
      : '0';
    info.availableBalance = availableBalanceVal !== undefined && availableBalanceVal !== null
      ? availableBalanceVal.toString()
      : '0';
    info.payScore = payScoreVal !== undefined && payScoreVal !== null ? Number(payScoreVal.toString()) : 0;
    info.isPayKey = isPayKeyVal !== undefined && isPayKeyVal !== null ? Boolean(isPayKeyVal) : false;
    info.isAdmin = isAdminVal !== undefined && isAdminVal !== null ? Boolean(isAdminVal) : false;
    info.remainQuota = remainQuotaVal !== undefined && remainQuotaVal !== null ? remainQuotaVal.toString() : '0';
    info.payLevel = payLevelVal !== undefined && payLevelVal !== null ? Number(payLevelVal.toString()) : 0;
    info.dailyLimit = dailyLimitVal !== undefined && dailyLimitVal !== null ? Number(dailyLimitVal.toString()) : 0;
    return info;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['id'] = this.id;
    json['username'] = this.username;
    json['nickname'] = this.nickname;
    json['trust_level'] = this.trustLevel;
    json['avatar_url'] = this.avatarUrl;
    json['total_receive'] = this.totalReceive;
    json['total_payment'] = this.totalPayment;
    json['total_transfer'] = this.totalTransfer;
    json['total_community'] = this.totalCommunity;
    json['community_balance'] = this.communityBalance;
    json['available_balance'] = this.availableBalance;
    json['pay_score'] = this.payScore;
    json['is_pay_key'] = this.isPayKey;
    json['is_admin'] = this.isAdmin;
    json['remain_quota'] = this.remainQuota;
    json['pay_level'] = this.payLevel;
    json['daily_limit'] = this.dailyLimit;
    return json;
  }
}

export class CdkUserInfo {
  id: number = 0;
  username: string = '';
  nickname: string = '';
  trustLevel: number = 0;
  avatarUrl: string = '';
  score: number = 0;

  static fromJson(json: Record<string, Object>): CdkUserInfo {
    const info: CdkUserInfo = new CdkUserInfo();
    const idVal = json['id'];
    const usernameVal = json['username'];
    const nicknameVal = json['nickname'];
    const trustLevelVal = json['trust_level'];
    const avatarUrlVal = json['avatar_url'];
    const scoreVal = json['score'];
    info.id = idVal !== undefined && idVal !== null ? Number(idVal.toString()) : 0;
    info.username = usernameVal !== undefined && usernameVal !== null ? usernameVal.toString() : '';
    info.nickname = nicknameVal !== undefined && nicknameVal !== null ? nicknameVal.toString() : '';
    info.trustLevel = trustLevelVal !== undefined && trustLevelVal !== null ? Number(trustLevelVal.toString()) : 0;
    info.avatarUrl = avatarUrlVal !== undefined && avatarUrlVal !== null ? avatarUrlVal.toString() : '';
    info.score = scoreVal !== undefined && scoreVal !== null ? Number(scoreVal.toString()) : 0;
    return info;
  }

  toJson(): Record<string, Object> {
    const json: Record<string, Object> = {};
    json['id'] = this.id;
    json['username'] = this.username;
    json['nickname'] = this.nickname;
    json['trust_level'] = this.trustLevel;
    json['avatar_url'] = this.avatarUrl;
    json['score'] = this.score;
    return json;
  }
}
