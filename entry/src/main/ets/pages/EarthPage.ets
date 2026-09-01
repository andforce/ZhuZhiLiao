import { webSocket, http } from '@kit.NetworkKit';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { geoLocationManager } from '@kit.LocationKit';
import { EarthNode, latLonToVec3, earthDetailForDistance } from '../earth/EarthModel';
import earthrender from 'libearthrender.so';

const EARTH_RADIUS = 1;
const WS_URL = 'wss://zhuzhiliao.aimfor.top/api/ws';
const API_BASE = 'https://zhuzhiliao.aimfor.top';

class Identity {
  id: string = '';
  code: string = '';
  token: string = '';
}

@Entry
@Component
struct EarthPage {
  private xComponentController: XComponentController = new XComponentController();
  @State autoRotate: boolean = true;
  @State nodes: EarthNode[] = [];
  @State selectedNode: EarthNode | undefined = undefined;
  private identity: Identity | undefined = undefined;
  private ws: webSocket.WebSocket | undefined = undefined;
  private wsState: number = 3;
  private earthRevision: number = 0;
  private requestSerial: number = 0;
  private snapshotTimerId: number = -1;
  private boundaryLoaded: boolean = false;
  @State meJoined: boolean = false;
  @State loadFailed: boolean = false;
  private lastDetail: number = -1;
  private detailTimerId: number = -1;

  aboutToAppear(): void {
    this.loadIdentityAndConnect();
    this.loadBoundaries();
    this.buildAndPushGrid();
  }

  aboutToDisappear(): void {
    if (this.snapshotTimerId >= 0) clearTimeout(this.snapshotTimerId);
    if (this.detailTimerId >= 0) clearTimeout(this.detailTimerId);
    this.closeWs();
    try { earthrender.cleanup(); } catch (_) {}
  }

  build() {
    Stack() {
      XComponent({
        id: 'earth',
        type: XComponentType.SURFACE,
        libraryname: 'earthrender',
        controller: this.xComponentController
      })
        .width('100%')
        .height('100%')
        .onLoad((event?: object) => {
          console.info('[Earth] XComponent onLoad, event=' + (event !== undefined ? 'yes' : 'no'));
          try {
            earthrender.registerCallback(event);
            earthrender.setAutoRotate(this.autoRotate);
            if (this.identity !== undefined) {
              earthrender.setMeCode(this.identity.code);
            }
            earthrender.setMeJoined(this.meJoined);
            const rect = this.xComponentController.getXComponentSurfaceRect();
            console.info('[Earth] surface rect w=' + rect.surfaceWidth + ' h=' + rect.surfaceHeight);
            this.xComponentController.setXComponentSurfaceSize({
              surfaceWidth: rect.surfaceWidth + 1,
              surfaceHeight: rect.surfaceHeight
            });
            setTimeout(() => {
              this.xComponentController.setXComponentSurfaceSize({
                surfaceWidth: rect.surfaceWidth,
                surfaceHeight: rect.surfaceHeight
              });
            }, 50);
          } catch (e) {
            console.error('[Earth] onLoad exception: ' + JSON.stringify(e));
          }
        })
        .onDestroy(() => {
          console.info('[Earth] XComponent onDestroy');
        })

      Column() {
        Row() {
          Button('关闭')
            .fontSize(12).fontColor('#f0e6d2')
            .backgroundColor('rgba(14,20,44,0.55)')
            .border({ width: 1, color: 'rgba(240,230,210,0.25)', radius: 999 })
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              try { this.getUIContext().getRouter().back(); } catch (_) {}
            })
          Text('哇声地球')
            .fontSize(16).fontColor('#f0e6d2').layoutWeight(1).textAlign(TextAlign.Center)
          Text('拖动旋转 · 双指缩放')
            .fontSize(11).fontColor('rgba(240,230,210,0.5)')
          Button(this.autoRotate ? '自转开' : '自转关')
            .fontSize(12)
            .fontColor(this.autoRotate ? '#1b0f0a' : '#f0e6d2')
            .backgroundColor(this.autoRotate ? '#e2603f' : 'rgba(14,20,44,0.55)')
            .border({ width: 1, color: this.autoRotate ? '#e2603f' : 'rgba(240,230,210,0.25)', radius: 999 })
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              this.autoRotate = !this.autoRotate;
              try { earthrender.setAutoRotate(this.autoRotate); } catch (_) {}
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 62, bottom: 12 })
        .linearGradient({ angle: 180, colors: [['rgba(4,8,16,0.75)', 0.0], ['transparent', 1.0]] })

        Blank()

        Column() { this.buildBottomCard() }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 48 })
          .linearGradient({ angle: 0, colors: [['transparent', 0.0], ['rgba(4,8,16,0.85)', 1.0]] })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#040810')
  }

  @Builder
  buildBottomCard() {
    Column() {
      if (this.selectedNode !== undefined) {
        Text(this.selectedNode.isMe ? '我' : '玩家·' + (this.selectedNode.code.length > 0 ? this.selectedNode.code : '未知'))
          .fontSize(16).fontColor('#f0e6d2').margin({ bottom: 8 })
      } else if (this.loadFailed) {
        Text('加载失败').fontSize(16).fontColor('#f0e6d2').margin({ bottom: 8 })
        Text('无法获取地球数据').fontSize(13).fontColor('rgba(240,230,210,0.7)')
      } else if (!this.meJoined) {
        Text('在地球上点亮我').fontSize(16).fontColor('#f0e6d2').margin({ bottom: 8 })
        Text('让你的哇声被全世界看见').fontSize(13).fontColor('rgba(240,230,210,0.7)').margin({ bottom: 14 })
        Button('加入哇声地球')
          .fontSize(14).fontColor('#1b0f0a').backgroundColor('#e2603f').borderRadius(999)
          .padding({ left: 28, right: 28, top: 11, bottom: 11 })
          .onClick(() => { this.joinEarth(); })
      } else {
        Text('已加入哇声地球').fontSize(16).fontColor('#f0e6d2').margin({ bottom: 8 })
        Text('摇动竹蝉，让这里产生回响').fontSize(13).fontColor('rgba(240,230,210,0.7)')
      }
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .border({ width: 1, color: 'rgba(240,230,210,0.18)', radius: 14 })
    .backgroundColor('rgba(14,20,44,0.7)')
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private buildAndPushGrid(): void {
    const R = EARTH_RADIUS * 1.002;
    const arr: number[] = [];
    for (let lat = -80; lat <= 80; lat += 20) {
      for (let lon = -180; lon < 180; lon += 5) {
        const p0 = latLonToVec3(lat, lon, R);
        const p1 = latLonToVec3(lat, lon + 5, R);
        const n0 = this.normalize3(p0.x, p0.y, p0.z);
        const n1 = this.normalize3(p1.x, p1.y, p1.z);
        arr.push(p0.x, p0.y, p0.z, n0[0], n0[1], n0[2], 0, 0);
        arr.push(p1.x, p1.y, p1.z, n1[0], n1[1], n1[2], 0, 0);
      }
    }
    for (let lon = -180; lon < 180; lon += 20) {
      for (let lat = -90; lat < 90; lat += 5) {
        const p0 = latLonToVec3(lat, lon, R);
        const p1 = latLonToVec3(lat + 5, lon, R);
        const n0 = this.normalize3(p0.x, p0.y, p0.z);
        const n1 = this.normalize3(p1.x, p1.y, p1.z);
        arr.push(p0.x, p0.y, p0.z, n0[0], n0[1], n0[2], 0, 0);
        arr.push(p1.x, p1.y, p1.z, n1[0], n1[1], n1[2], 0, 0);
      }
    }
    try { earthrender.updateGridData(new Float32Array(arr)); } catch (e) {
      console.error('[Earth] pushGrid failed: ' + JSON.stringify(e));
    }
  }

  private normalize3(x: number, y: number, z: number): number[] {
    const len = Math.sqrt(x * x + y * y + z * z);
    if (len === 0) return [0, 0, 0];
    return [x / len, y / len, z / len];
  }

  private pushNodesToNative(): void {
    if (this.nodes.length === 0) return;
    const meCode = this.identity !== undefined ? this.identity.code : '';
    const data = new Float32Array(this.nodes.length * 4);
    for (let i = 0; i < this.nodes.length; i++) {
      const node = this.nodes[i];
      data[i * 4] = node.latitude;
      data[i * 4 + 1] = node.longitude;
      data[i * 4 + 2] = node.score;
      data[i * 4 + 3] = (node.isMe || (meCode.length > 0 && node.code === meCode)) ? 1.0 : 0.0;
    }
    try { earthrender.updateNodes(data); } catch (e) {
      console.error('[Earth] pushNodes failed: ' + JSON.stringify(e));
    }
  }

  private loadBoundaries(): void {
    if (this.boundaryLoaded) return;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      context.resourceManager.getRawFileContent('3d/vendor/ne_110m_admin_0_countries.geojson').then((content: Uint8Array) => {
        this.parseGeoJSONAndPush(util.TextDecoder.create('utf-8').decodeToString(content));
      }).catch((err: BusinessError) => {
        console.error('[Earth] read GeoJSON failed: ' + JSON.stringify(err));
      });
    } catch (err) {
      console.error('[Earth] loadBoundaries error: ' + JSON.stringify(err));
    }
  }

  private parseGeoJSONAndPush(jsonStr: string): void {
    const R = EARTH_RADIUS * 1.006;
    const cleaned = jsonStr.replace(/"bbox"\s*:\s*\[[\s\S]*?\]/g, '""');
    const pattern = new RegExp('\\[\\s*(-?\\d+\\.?\\d*)\\s*,\\s*(-?\\d+\\.?\\d*)\\s*\\]', 'g');
    const coords: number[][] = [];
    const endPos: number[] = [];
    const startPos: number[] = [];
    let m = pattern.exec(cleaned);
    while (m !== null) {
      coords.push([parseFloat(m[1]), parseFloat(m[2])]);
      startPos.push(m.index);
      endPos.push(pattern.lastIndex);
      m = pattern.exec(cleaned);
    }
    const arr: number[] = [];
    for (let i = 0; i < coords.length - 1; i++) {
      const gap = cleaned.substring(endPos[i], startPos[i + 1]);
      if (gap.indexOf(']]') >= 0) continue;
      if (gap.indexOf('],[') >= 0) continue;
      if (gap.indexOf('"') >= 0) continue;
      const lon0 = coords[i][0], lat0 = coords[i][1];
      const lon1 = coords[i + 1][0], lat1 = coords[i + 1][1];
      if (Math.abs(lon0 - lon1) > 10 || Math.abs(lat0 - lat1) > 10) continue;
      const p0 = latLonToVec3(lat0, lon0, R);
      const p1 = latLonToVec3(lat1, lon1, R);
      const n0 = this.normalize3(p0.x, p0.y, p0.z);
      const n1 = this.normalize3(p1.x, p1.y, p1.z);
      arr.push(p0.x, p0.y, p0.z, n0[0], n0[1], n0[2], 0, 0);
      arr.push(p1.x, p1.y, p1.z, n1[0], n1[1], n1[2], 0, 0);
    }
    try { earthrender.updateBoundaryData(new Float32Array(arr)); } catch (e) {
      console.error('[Earth] pushBoundary failed: ' + JSON.stringify(e));
    }
    this.boundaryLoaded = true;
    console.info('[Earth] boundaries loaded, segments: ' + (arr.length / 16));
  }

  private appendPolygon(polygonData: Object, radius: number, arr: number[]): void {
    const rings = polygonData as Object[];
    for (let ri = 0; ri < rings.length; ri++) {
      const ring = rings[ri] as Object[];
      if (ring.length < 2) continue;
      let prevX = 0.0, prevY = 0.0, prevZ = 0.0;
      let hasPrev = false;
      for (let ci = 0; ci < ring.length; ci++) {
        const coord = ring[ci] as number[];
        if (coord.length < 2) continue;
        const lon = coord[0];
        const lat = coord[1];
        const p = latLonToVec3(lat, lon, radius);
        const n = this.normalize3(p.x, p.y, p.z);
        if (hasPrev) {
          const n0 = this.normalize3(prevX, prevY, prevZ);
          arr.push(prevX, prevY, prevZ, n0[0], n0[1], n0[2], 0, 0);
          arr.push(p.x, p.y, p.z, n[0], n[1], n[2], 0, 0);
        }
        prevX = p.x; prevY = p.y; prevZ = p.z;
        hasPrev = true;
      }
    }
  }

  private loadIdentityAndConnect(): void {
    console.info('[Earth] loadIdentityAndConnect');
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const store = preferences.getPreferencesSync(context, { name: 'hmos_prefs' });
      const raw = store.getSync('hmos_identity', '') as string;
      console.info('[Earth] stored identity raw length=' + raw.length);
      if (raw.length > 0) {
        const obj = JSON.parse(raw) as Record<string, string>;
        if (obj['id'] !== undefined && obj['code'] !== undefined && obj['token'] !== undefined) {
          this.identity = new Identity();
          this.identity.id = obj['id'] ?? '';
          this.identity.code = obj['code'] ?? '';
          this.identity.token = obj['token'] ?? '';
          console.info('[Earth] identity loaded, code=' + this.identity.code);
          try { earthrender.setMeCode(this.identity.code); } catch (_) {}
          this.connectWs();
          return;
        }
      }
    } catch (_) {
      console.error('[Earth] loadIdentity exception');
    }
    console.info('[Earth] no stored identity, creating new');
    this.createIdentity();
  }

  private createIdentity(): void {
    console.info('[Earth] createIdentity request');
    const httpRequest = http.createHttp();
    httpRequest.request(API_BASE + '/api/players', {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 15000
    }).then((resp: http.HttpResponse) => {
      const body = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      console.info('[Earth] createIdentity response code=' + resp.responseCode);
      const data = JSON.parse(body) as Record<string, string>;
      if (data['id'] !== undefined && data['code'] !== undefined && data['token'] !== undefined) {
        this.identity = new Identity();
        this.identity.id = data['id'] ?? '';
        this.identity.code = data['code'] ?? '';
        this.identity.token = data['token'] ?? '';
        console.info('[Earth] createIdentity success, code=' + this.identity.code);
        try {
          const context = getContext(this) as common.UIAbilityContext;
          const store = preferences.getPreferencesSync(context, { name: 'hmos_prefs' });
          store.putSync('hmos_identity', JSON.stringify({
            'id': this.identity.id, 'code': this.identity.code, 'token': this.identity.token
          }));
          store.flush();
        } catch (_) {}
        try { earthrender.setMeCode(this.identity.code); } catch (_) {}
        this.connectWs();
      } else {
        console.error('[Earth] createIdentity response missing fields');
      }
    }).catch((err: BusinessError) => {
      console.error('[Earth] createIdentity failed: ' + JSON.stringify(err));
    }).then(() => { httpRequest.destroy(); });
  }

  private connectWs(): void {
    if (this.ws !== undefined && this.wsState === 1) return;
    this.closeWs();
    console.info('[Earth] connectWs');
    try {
      this.ws = webSocket.createWebSocket();
      this.wsState = 0;
      this.ws.on('open', () => {
        this.wsState = 1;
        console.info('[Earth] WS open');
        this.requestSnapshot();
      });
      this.ws.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
        this.onWsMessage(typeof data === 'string' ? data : String(data));
      });
      this.ws.on('close', () => {
        this.wsState = 3;
        console.info('[Earth] WS closed');
      });
      this.ws.on('error', () => {
        this.wsState = 3;
        console.error('[Earth] WS error');
      });
      const header: Record<string, string> = {};
      if (this.identity !== undefined) {
        header['Authorization'] = 'Bearer ' + this.identity.token;
      }
      this.ws.connect(WS_URL, { header }).catch((e: BusinessError) => {
        console.error('[Earth] WS connect failed: ' + JSON.stringify(e));
        this.wsState = 3;
      });
    } catch (e) {
      console.error('[Earth] connectWs exception: ' + JSON.stringify(e));
      this.wsState = 3;
    }
  }

  private closeWs(): void {
    if (this.ws !== undefined) {
      try {
        this.ws.off('open'); this.ws.off('message'); this.ws.off('close'); this.ws.off('error');
        if (this.wsState === 1) this.ws.close({ code: 1001, reason: 'going away' });
      } catch (_) {}
      this.ws = undefined;
    }
    this.wsState = 3;
  }

  private onWsMessage(raw: string): void {
    let m: Record<string, Object>;
    try { m = JSON.parse(raw) as Record<string, Object>; } catch (_) { return; }
    const t = typeof m['t'] === 'string' ? m['t'] as string : '';
    if (t === 'player') {
      const enabled = m['earthEnabled'];
      this.meJoined = enabled === true || enabled === 1 || enabled === 'true';
      try { earthrender.setMeJoined(this.meJoined); } catch (_) {}
    } else if (t === 'earth_snapshot') {
      try { this.handleEarthSnapshot(m); } catch (e) {
        console.error('[Earth] handleEarthSnapshot exception: ' + JSON.stringify(e));
      }
    } else if (t === 'earth_revision') {
      const rev = typeof m['revision'] === 'number' ? m['revision'] as number : -1;
      if (rev >= 0 && rev !== this.earthRevision) {
        this.earthRevision = rev;
        this.requestSnapshot();
      }
    }
  }

  private handleEarthSnapshot(m: Record<string, Object>): void {
    const rawNodes = m['nodes'];
    if (rawNodes === undefined || rawNodes === null) return;
    if (typeof rawNodes !== 'object' || !Array.isArray(rawNodes)) return;
    const arr = rawNodes as Array<Object>;
    const parsed: EarthNode[] = [];
    const meCode = this.identity !== undefined ? this.identity.code : '';
    for (let i = 0; i < arr.length; i++) {
      try {
        const item = arr[i];
        if (typeof item !== 'object' || item === null) continue;
        const r = item as Record<string, Object>;
        const node = EarthNode.fromRecord(r);
        if (meCode.length > 0 && node.code === meCode) node.isMe = true;
        parsed.push(node);
      } catch (_) { continue; }
    }
    this.nodes = parsed;
    this.loadFailed = false;
    const rev = typeof m['revision'] === 'number' ? m['revision'] as number : -1;
    if (rev >= 0) this.earthRevision = rev;
    this.pushNodesToNative();
  }

  private requestSnapshot(): void {
    console.info('[Earth] requestSnapshot, ws=' + (this.ws !== undefined ? 'yes' : 'no') + ' state=' + this.wsState);
    if (this.ws === undefined || this.wsState !== 1) return;
    this.requestSerial++;
    const msg = JSON.stringify({
      't': 'earth_view', 'requestID': this.uuid(),
      'detail': earthDetailForDistance(3.25), 'bounds': []
    });
    console.info('[Earth] requestSnapshot sending, msgLen=' + msg.length);
    this.ws.send(msg).catch((e: BusinessError) => {
      console.error('[Earth] WS send failed: ' + JSON.stringify(e));
    });
    if (this.snapshotTimerId >= 0) clearTimeout(this.snapshotTimerId);
    this.snapshotTimerId = setTimeout(() => {
      this.snapshotTimerId = -1;
      if (this.nodes.length === 0) this.loadFailed = true;
    }, 10000);
  }

  private joinEarth(): void {
    try {
      console.info('[Earth] joinEarth called, identity=' + (this.identity !== undefined ? 'yes' : 'no'));
      if (this.identity === undefined) { this.createIdentityAndJoin(); return; }
      this.requestLocationAndJoin();
    } catch (e) {
      console.error('[Earth] joinEarth top-level exception: ' + JSON.stringify(e));
    }
  }

  private createIdentityAndJoin(): void {
    console.info('[Earth] createIdentityAndJoin');
    const httpRequest = http.createHttp();
    httpRequest.request(API_BASE + '/api/players', {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000, readTimeout: 15000
    }).then((resp: http.HttpResponse) => {
      const body = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      console.info('[Earth] createIdentityAndJoin response code=' + resp.responseCode);
      const data = JSON.parse(body) as Record<string, string>;
      if (data['id'] !== undefined && data['code'] !== undefined && data['token'] !== undefined) {
        this.identity = new Identity();
        this.identity.id = data['id'] ?? '';
        this.identity.code = data['code'] ?? '';
        this.identity.token = data['token'] ?? '';
        try {
          const context = getContext(this) as common.UIAbilityContext;
          const store = preferences.getPreferencesSync(context, { name: 'hmos_prefs' });
          store.putSync('hmos_identity', JSON.stringify({
            'id': this.identity.id, 'code': this.identity.code, 'token': this.identity.token
          }));
          store.flush();
        } catch (e) {
          console.error('[Earth] saveIdentity exception: ' + JSON.stringify(e));
        }
        try { earthrender.setMeCode(this.identity.code); } catch (_) {}
        this.connectWs();
        this.requestLocationAndJoin();
      }
    }).catch((err: BusinessError) => {
      console.error('[Earth] createIdentityAndJoin failed: ' + JSON.stringify(err));
      this.loadFailed = true;
    }).then(() => { httpRequest.destroy(); });
  }

  private requestLocationAndJoin(): void {
    console.info('[Earth] requestLocationAndJoin');
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const atManager = abilityAccessCtrl.createAtManager();
      atManager.requestPermissionsFromUser(context, ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']).then((result) => {
        let granted = false;
        for (let i = 0; i < result.authResults.length; i++) {
          if (result.authResults[i] === 0) { granted = true; break; }
        }
        console.info('[Earth] permission result, granted=' + granted);
        if (granted) { this.getLocationAndJoin(); } else { this.doJoinEarth('v1:0:0'); }
      }).catch((e: BusinessError) => {
        console.error('[Earth] requestPermissions failed: ' + JSON.stringify(e));
        this.doJoinEarth('v1:0:0');
      });
    } catch (e) {
      console.error('[Earth] requestLocationAndJoin exception: ' + JSON.stringify(e));
      this.doJoinEarth('v1:0:0');
    }
  }

  private getLocationAndJoin(): void {
    console.info('[Earth] getLocationAndJoin');
    try {
      geoLocationManager.getCurrentLocation({
        'priority': geoLocationManager.LocationRequestPriority.LOW_POWER,
        'scenario': geoLocationManager.LocationRequestScenario.UNSET,
        'maxAccuracy': 5000
      }).then((loc: geoLocationManager.Location) => {
        console.info('[Earth] got location: ' + loc.latitude + ',' + loc.longitude);
        this.doJoinEarth('v1:' + loc.latitude.toFixed(2) + ':' + loc.longitude.toFixed(2));
      }).catch((e: BusinessError) => {
        console.error('[Earth] getLocation failed: ' + JSON.stringify(e));
        this.doJoinEarth('v1:0:0');
      });
    } catch (e) {
      console.error('[Earth] getLocationAndJoin exception: ' + JSON.stringify(e));
      this.doJoinEarth('v1:0:0');
    }
  }

  private doJoinEarth(cellID: string): void {
    console.info('[Earth] doJoinEarth, cellID=' + cellID + ', identity=' + (this.identity !== undefined ? 'yes' : 'no'));
    if (this.identity === undefined) return;
    try {
      const httpRequest = http.createHttp();
      console.info('[Earth] doJoinEarth sending PUT...');
      httpRequest.request(API_BASE + '/api/players/me/earth', {
        method: http.RequestMethod.PUT,
        header: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + this.identity.token },
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify({ 'enabled': true, 'cellID': cellID }),
        connectTimeout: 15000, readTimeout: 15000
      }).then((resp: http.HttpResponse) => {
        console.info('[Earth] joinEarth response code=' + resp.responseCode);
        if (resp.responseCode >= 200 && resp.responseCode < 300) {
          this.meJoined = true;
          try { earthrender.setMeJoined(true); } catch (_) {}
          console.info('[Earth] meJoined=true, about to requestSnapshot');
          this.requestSnapshot();
          console.info('[Earth] requestSnapshot returned');
        }
      }).catch((err: BusinessError) => {
        console.error('[Earth] joinEarth failed: ' + JSON.stringify(err));
      }).then(() => { httpRequest.destroy(); });
    } catch (e) {
      console.error('[Earth] doJoinEarth exception: ' + JSON.stringify(e));
    }
  }

  private uuid(): string {
    const chars = '0123456789abcdef';
    let result = '';
    for (let i = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) result += '-';
      else if (i === 14) result += '4';
      else if (i === 19) result += chars.charAt(Math.floor(Math.random() * 4) + 8);
      else result += chars.charAt(Math.floor(Math.random() * 16));
    }
    return result;
  }
}
