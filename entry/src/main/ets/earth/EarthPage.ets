import { router } from '@kit.ArkUI';
import { webSocket, http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { display } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import {
  EarthNode, GeoPoint, ProjectedLine, ProjectedDot, RippleState,
  latLonToVec3, earthDetailForDistance
} from '../earth/EarthModel';

const EARTH_RADIUS = 2;
const WS_URL = 'wss://zhuzhiliao.aimfor.top/api/ws';
const API_BASE = 'https://zhuzhiliao.aimfor.top';
const MIN_DIST = 1.72;
const MAX_DIST = 4.25;

class Identity {
  id: string = '';
  code: string = '';
  token: string = '';
}

export @Entry
@Component
struct EarthPage {
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  @State canvasW: number = 360;
  @State canvasH: number = 640;
  private cameraDistance: number = 3.75;
  private rotX: number = 0.3;
  private rotY: number = 0;
  private autoRotate: boolean = true;
  private lastInteractionTime: number = 0;
  private timerId: number = -1;
  private nodes: EarthNode[] = [];
  private selectedNode: EarthNode | undefined = undefined;
  private identity: Identity | undefined = undefined;
  private ws: webSocket.WebSocket | undefined = undefined;
  private wsState: number = 3;
  private earthRevision: number = 0;
  private requestSerial: number = 0;
  private snapshotTimerId: number = -1;
  private boundaryLines: ProjectedLine[] = [];
  private boundaryLoaded: boolean = false;
  private ripples: RippleState[] = [];
  private meJoined: boolean = false;
  private loadFailed: boolean = false;
  private lastDetail: number = -1;
  private detailTimerId: number = -1;
  private fov: number = 41;
  private lastFrameTime: number = 0;
  private pinchStartDistance: number = 3.75;

  aboutToAppear(): void {
    const screenInfo: display.Display = display.getDefaultDisplaySync();
    this.canvasW = screenInfo.width / screenInfo.densityPixels;
    this.canvasH = screenInfo.height / screenInfo.densityPixels;
    this.lastInteractionTime = Date.now();
    this.ripples = [
      RippleState.create(0, 0, 0),
      RippleState.create(0, 0, 0.33),
      RippleState.create(0, 0, 0.66),
    ];
    this.loadIdentityAndConnect();
    this.loadBoundaries();
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) clearInterval(this.timerId);
    if (this.snapshotTimerId >= 0) clearTimeout(this.snapshotTimerId);
    if (this.detailTimerId >= 0) clearTimeout(this.detailTimerId);
    this.closeWs();
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.timerId = setInterval(() => { this.gameLoop(); }, 33);
        })
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {
                this.lastInteractionTime = Date.now();
                this.pinchStartDistance = this.cameraDistance;
              })
              .onActionUpdate((e: PinchGestureEvent) => {
                this.lastInteractionTime = Date.now();
                if (e.scale > 0) {
                  this.cameraDistance = this.clamp(this.pinchStartDistance / e.scale, MIN_DIST, MAX_DIST);
                }
              }),
            PanGesture({ fingers: 1 })
              .onActionStart(() => {
                this.lastInteractionTime = Date.now();
              })
              .onActionUpdate((e: PanGestureEvent) => {
                this.lastInteractionTime = Date.now();
                this.rotY += e.offsetX * 0.0003;
                this.rotX = this.clamp(this.rotX + e.offsetY * 0.0003, -Math.PI / 2, Math.PI / 2);
              })
          )
        )

      Column() {
        Row() {
          Button('关闭')
            .fontSize(12)
            .fontColor('#f0e6d2')
            .backgroundColor('rgba(14,20,44,0.55)')
            .border({ width: 1, color: 'rgba(240,230,210,0.25)', radius: 999 })
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              this.getUIContext().getRouter().back();
            })
          Text('哇声地球')
            .fontSize(16)
            .fontColor('#f0e6d2')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('拖动旋转 · 双指缩放')
            .fontSize(11)
            .fontColor('rgba(240,230,210,0.5)')
          Button(this.autoRotate ? '自转开' : '自转关')
            .fontSize(12)
            .fontColor(this.autoRotate ? '#1b0f0a' : '#f0e6d2')
            .backgroundColor(this.autoRotate ? '#e2603f' : 'rgba(14,20,44,0.55)')
            .border({ width: 1, color: this.autoRotate ? '#e2603f' : 'rgba(240,230,210,0.25)', radius: 999 })
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              this.autoRotate = !this.autoRotate;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 62, bottom: 12 })
        .linearGradient({
          angle: 180,
          colors: [['rgba(4,8,16,0.75)', 0.0], ['transparent', 1.0]]
        })

        Blank()

        Column() {
          this.buildBottomCard()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 48 })
        .linearGradient({
          angle: 0,
          colors: [['transparent', 0.0], ['rgba(4,8,16,0.85)', 1.0]]
        })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
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
          .fontSize(16)
          .fontColor('#f0e6d2')
          .margin({ bottom: 8 })
        if (this.selectedNode.score > 0) {
          Text('哇数 ' + this.selectedNode.score)
            .fontSize(13)
            .fontColor('rgba(240,230,210,0.7)')
            .margin({ top: 4 })
        }
        if (this.selectedNode.activeUntil > 0) {
          Text('活跃中')
            .fontSize(13)
            .fontColor('rgba(240,230,210,0.7)')
            .margin({ top: 4 })
        }
      } else if (this.loadFailed) {
        Text('加载失败')
          .fontSize(16)
          .fontColor('#f0e6d2')
          .margin({ bottom: 8 })
        Text('无法获取地球数据')
          .fontSize(13)
          .fontColor('rgba(240,230,210,0.7)')
      } else if (!this.meJoined) {
        Text('在地球上点亮我')
          .fontSize(16)
          .fontColor('#f0e6d2')
          .margin({ bottom: 8 })
        Text('让你的哇声被全世界看见')
          .fontSize(13)
          .fontColor('rgba(240,230,210,0.7)')
          .margin({ bottom: 14 })
        Button('加入哇声地球')
          .fontSize(14)
          .fontColor('#1b0f0a')
          .backgroundColor('#e2603f')
          .borderRadius(999)
          .padding({ left: 28, right: 28, top: 11, bottom: 11 })
          .onClick(() => { this.joinEarth(); })
      } else {
        Text('已加入哇声地球')
          .fontSize(16)
          .fontColor('#f0e6d2')
          .margin({ bottom: 8 })
        Text('摇动竹蝉，让这里产生回响')
          .fontSize(13)
          .fontColor('rgba(240,230,210,0.7)')
      }
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .border({ width: 1, color: 'rgba(240,230,210,0.18)', radius: 14 })
    .backgroundColor('rgba(14,20,44,0.7)')
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private clamp(v: number, lo: number, hi: number): number {
    return v < lo ? lo : v > hi ? hi : v;
  }

  private rotatePoint(p: GeoPoint): GeoPoint {
    const cosY = Math.cos(this.rotY);
    const sinY = Math.sin(this.rotY);
    const x1 = p.x * cosY - p.z * sinY;
    const z1 = p.x * sinY + p.z * cosY;
    const cosX = Math.cos(this.rotX);
    const sinX = Math.sin(this.rotX);
    const y1 = p.y * cosX - z1 * sinX;
    const z2 = p.y * sinX + z1 * cosX;
    return GeoPoint.create(x1, y1, z2);
  }

  private project(p: GeoPoint): ProjectedLine {
    const result: ProjectedLine = { x1: 0, y1: 0, x2: 0, y2: 0, visible: false };
    const rotated = this.rotatePoint(p);
    if (rotated.z <= 0.1) {
      return result;
    }
    const fovRad = (this.fov / 2) * Math.PI / 180;
    const scale = 1 / Math.tan(fovRad);
    const projScale = (this.canvasH / 2) * scale / this.cameraDistance;
    result.x1 = rotated.x * projScale / (this.canvasW / this.canvasH) + this.canvasW / 2;
    result.y1 = -rotated.y * projScale + this.canvasH / 2;
    result.visible = true;
    return result;
  }

  private projectPoint(p: GeoPoint): ProjectedDot {
    const dot: ProjectedDot = { screenX: 0, screenY: 0, screenR: 0, isMe: false, node: new EarthNode() };
    const rotated = this.rotatePoint(p);
    if (rotated.z <= 0.1) {
      return dot;
    }
    const fovRad = (this.fov / 2) * Math.PI / 180;
    const scale = 1 / Math.tan(fovRad);
    const projScale = (this.canvasH / 2) * scale / this.cameraDistance;
    dot.screenX = rotated.x * projScale / (this.canvasW / this.canvasH) + this.canvasW / 2;
    dot.screenY = -rotated.y * projScale + this.canvasH / 2;
    dot.screenR = 6;
    return dot;
  }

  private gameLoop(): void {
    const now = Date.now();
    const delta = this.lastFrameTime > 0 ? Math.min((now - this.lastFrameTime) / 1000, 0.05) : 0.016;
    this.lastFrameTime = now;

    if (this.autoRotate && now - this.lastInteractionTime > 3000) {
      this.rotY += delta * 0.055;
    }

    const detail = earthDetailForDistance(this.cameraDistance);
    if (detail !== this.lastDetail) {
      this.lastDetail = detail;
      if (this.detailTimerId >= 0) clearTimeout(this.detailTimerId);
      this.detailTimerId = setTimeout(() => {
        this.detailTimerId = -1;
        this.requestSnapshot();
      }, 180);
    }

    this.draw();
  }

  private draw(): void {
    const c = this.ctx;
    c.clearRect(0, 0, this.canvasW, this.canvasH);

    const bgGrad = c.createLinearGradient(0, 0, 0, this.canvasH);
    bgGrad.addColorStop(0, '#040810');
    bgGrad.addColorStop(1, '#0a1028');
    c.fillStyle = bgGrad;
    c.fillRect(0, 0, this.canvasW, this.canvasH);

    let seed = 2024;
    const rnd = (): number => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
    c.fillStyle = '#e8ecff';
    for (let i = 0; i < 80; i++) {
      const sx = rnd() * this.canvasW;
      const sy = rnd() * this.canvasH * 0.7;
      const sr = 0.5 + rnd() * 0.8;
      const sa = 0.15 + rnd() * 0.35;
      c.globalAlpha = sa;
      c.beginPath();
      c.arc(sx, sy, sr, 0, Math.PI * 2);
      c.fill();
    }
    c.globalAlpha = 1;

    this.drawGridLines(c);
    this.drawBoundaries(c);
    this.drawNodes(c);
    this.drawRipples(c);
  }

  private drawGridLines(c: CanvasRenderingContext2D): void {
    c.strokeStyle = 'rgba(74,122,184,0.25)';
    c.lineWidth = 0.5;

    for (let lat = -80; lat <= 80; lat += 20) {
      let started = false;
      for (let lon = -180; lon <= 180; lon += 5) {
        const p = latLonToVec3(lat, lon, EARTH_RADIUS * 1.002);
        const proj = this.project(p);
        if (proj.visible) {
          if (!started) {
            c.beginPath();
            c.moveTo(proj.x1, proj.y1);
            started = true;
          } else {
            c.lineTo(proj.x1, proj.y1);
          }
        } else {
          if (started) { c.stroke(); started = false; }
        }
      }
      if (started) c.stroke();
    }

    for (let lon = -180; lon < 180; lon += 20) {
      let started = false;
      for (let lat = -90; lat <= 90; lat += 5) {
        const p = latLonToVec3(lat, lon, EARTH_RADIUS * 1.002);
        const proj = this.project(p);
        if (proj.visible) {
          if (!started) {
            c.beginPath();
            c.moveTo(proj.x1, proj.y1);
            started = true;
          } else {
            c.lineTo(proj.x1, proj.y1);
          }
        } else {
          if (started) { c.stroke(); started = false; }
        }
      }
      if (started) c.stroke();
    }
  }

  private drawBoundaries(c: CanvasRenderingContext2D): void {
    if (this.boundaryLines.length === 0) return;
    c.strokeStyle = 'rgba(106,154,200,0.35)';
    c.lineWidth = 0.6;
    c.beginPath();
    for (let i = 0; i < this.boundaryLines.length; i++) {
      const line = this.boundaryLines[i];
      if (!line.visible) continue;
      c.moveTo(line.x1, line.y1);
      c.lineTo(line.x2, line.y2);
    }
    c.stroke();
  }

  private drawNodes(c: CanvasRenderingContext2D): void {
    const meCode = this.identity !== undefined ? this.identity.code : '';
    for (let i = 0; i < this.nodes.length; i++) {
      const node = this.nodes[i];
      if (node.latitude === 0 && node.longitude === 0) continue;
      const isMe = node.isMe || (meCode.length > 0 && node.code === meCode);
      const p = latLonToVec3(node.latitude, node.longitude, EARTH_RADIUS * 1.01);
      const dot = this.projectPoint(p);
      if (dot.screenR === 0) continue;

      const glowR = dot.screenR * 2.5;
      c.globalAlpha = 0.25;
      c.fillStyle = isMe ? '#FAB84A' : '#5CDBD6';
      c.beginPath();
      c.arc(dot.screenX, dot.screenY, glowR, 0, Math.PI * 2);
      c.fill();

      c.globalAlpha = 0.85;
      c.fillStyle = isMe ? '#FAB84A' : '#5CDBD6';
      c.beginPath();
      c.arc(dot.screenX, dot.screenY, dot.screenR, 0, Math.PI * 2);
      c.fill();

      if (isMe) {
        for (let j = 0; j < this.ripples.length; j++) {
          this.ripples[j].screenX = dot.screenX;
          this.ripples[j].screenY = dot.screenY;
        }
      }
    }
    c.globalAlpha = 1;
  }

  private drawRipples(c: CanvasRenderingContext2D): void {
    const now = Date.now();
    const cycle = (now / 2800) % 1;
    for (let i = 0; i < this.ripples.length; i++) {
      const rp = this.ripples[i];
      if (rp.screenX === 0 && rp.screenY === 0) continue;
      const t = (cycle + rp.phase) % 1;
      const scale = 1 + t * 8;
      const opacity = (1 - t) * 0.6;
      c.globalAlpha = opacity;
      c.strokeStyle = '#FAB84A';
      c.lineWidth = 1.5;
      c.beginPath();
      c.arc(rp.screenX, rp.screenY, 6 * scale, 0, Math.PI * 2);
      c.stroke();
    }
    c.globalAlpha = 1;
  }

  private loadBoundaries(): void {
    if (this.boundaryLoaded) return;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const rm = context.resourceManager;
      rm.getRawFileContent('3d/vendor/ne_110m_admin_0_countries.geojson').then((content: Uint8Array) => {
        const textDecoder = util.TextDecoder.create('utf-8');
        const jsonStr = textDecoder.decodeToString(content);
        this.parseGeoJSON(jsonStr);
      }).catch((err: BusinessError) => {
        console.error('[Earth] read GeoJSON failed: ' + JSON.stringify(err));
      });
    } catch (err) {
      console.error('[Earth] loadBoundaries error: ' + JSON.stringify(err));
    }
  }

  private parseGeoJSON(jsonStr: string): void {
    const lines: ProjectedLine[] = [];
    const R = EARTH_RADIUS * 1.003;
    let pos = 0;
    const len = jsonStr.length;

    // Simple GeoJSON parser: extract coordinate arrays from geometry objects
    // We look for "coordinates" keys and parse the nested arrays
    const coordPattern = new RegExp('"coordinates"\\s*:\\s*\\[');
    let match = coordPattern.exec(jsonStr);
    while (match !== null) {
      const startIdx = match.index + match[0].length - 1;
      const coordsStr = this.extractBalancedArray(jsonStr, startIdx);
      if (coordsStr.length > 0) {
        this.parseCoordArray(coordsStr, R, lines);
      }
      pos = startIdx + 1;
      coordPattern.lastIndex = pos;
      match = coordPattern.exec(jsonStr);
    }

    this.boundaryLines = lines;
    this.boundaryLoaded = true;
    console.info('[Earth] boundaries loaded, lines: ' + lines.length);
  }

  private extractBalancedArray(s: string, startIdx: number): string {
    let depth = 0;
    let i = startIdx;
    while (i < s.length) {
      if (s.charAt(i) === '[') depth++;
      else if (s.charAt(i) === ']') {
        depth--;
        if (depth === 0) return s.substring(startIdx, i + 1);
      }
      i++;
    }
    return '';
  }

  private parseCoordArray(coordsStr: string, radius: number, lines: ProjectedLine[]): void {
    // Extract all [lon, lat] pairs from the coordinate string
    // Pattern: find number pairs inside brackets
    const numPattern = new RegExp('\\[\\s*(-?\\d+\\.?\\d*)\\s*,\\s*(-?\\d+\\.?\\d*)\\s*\\]', 'g');
    const pairs: Array<Array<number>> = [];
    let m = numPattern.exec(coordsStr);
    while (m !== null) {
      const lon = parseFloat(m[1]);
      const lat = parseFloat(m[2]);
      const pair: Array<number> = [lon, lat];
      pairs.push(pair);
      m = numPattern.exec(coordsStr);
    }

    // Draw lines between consecutive pairs (within same ring)
    // We detect ring breaks by checking distance between consecutive points
    for (let i = 0; i < pairs.length - 1; i++) {
      const lon0 = pairs[i][0];
      const lat0 = pairs[i][1];
      const lon1 = pairs[i + 1][0];
      const lat1 = pairs[i + 1][1];
      // Skip if distance > 10 degrees (ring boundary)
      if (Math.abs(lon0 - lon1) > 10 || Math.abs(lat0 - lat1) > 10) continue;
      const v0 = latLonToVec3(lat0, lon0, radius);
      const v1 = latLonToVec3(lat1, lon1, radius);
      const proj0 = this.project(v0);
      const proj1 = this.project(v1);
      const line: ProjectedLine = {
        x1: proj0.x1, y1: proj0.y1,
        x2: proj1.x1, y2: proj1.y1,
        visible: proj0.visible && proj1.visible
      };
      lines.push(line);
    }
  }

  private loadIdentityAndConnect(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const store = preferences.getPreferencesSync(context, { name: 'hmos_prefs' });
      const raw = store.getSync('hmos_identity', '') as string;
      if (raw.length > 0) {
        const obj = JSON.parse(raw) as Record<string, string>;
        if (obj['id'] !== undefined && obj['code'] !== undefined && obj['token'] !== undefined) {
          this.identity = new Identity();
          this.identity.id = obj['id'] ?? '';
          this.identity.code = obj['code'] ?? '';
          this.identity.token = obj['token'] ?? '';
          this.connectWs();
          return;
        }
      }
    } catch (_) {}

    this.createIdentity();
  }

  private createIdentity(): void {
    const httpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 15000
    };
    httpRequest.request(API_BASE + '/api/players', options).then((resp: http.HttpResponse) => {
      const body = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
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
        } catch (_) {}
        this.connectWs();
      }
    }).catch((err: BusinessError) => {
      console.error('[Earth] createIdentity failed: ' + JSON.stringify(err));
    }).then(() => {
      httpRequest.destroy();
    });
  }

  private connectWs(): void {
    if (this.ws !== undefined && this.wsState === 1) return;
    this.closeWs();
    try {
      this.ws = webSocket.createWebSocket();
      this.wsState = 0;
      this.ws.on('open', () => {
        this.wsState = 1;
        console.info('[Earth] WS opened');
        this.requestSnapshot();
      });
      this.ws.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
        const msg = typeof data === 'string' ? data : String(data);
        this.onWsMessage(msg);
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
      this.ws.connect(WS_URL, { header }).catch((err: BusinessError) => {
        this.wsState = 3;
        console.error('[Earth] WS connect failed: ' + JSON.stringify(err));
      });
    } catch (err) {
      console.error('[Earth] connectWs error: ' + JSON.stringify(err));
    }
  }

  private closeWs(): void {
    if (this.ws !== undefined) {
      try {
        this.ws.off('open');
        this.ws.off('message');
        this.ws.off('close');
        this.ws.off('error');
        if (this.wsState === 1) {
          this.ws.close({ code: 1001, reason: 'going away' });
        }
      } catch (_) {}
      this.ws = undefined;
    }
    this.wsState = 3;
  }

  private wsSend(obj: Record<string, Object>): void {
    if (this.ws === undefined || this.wsState !== 1) return;
    const s = JSON.stringify(obj);
    this.ws.send(s).catch(() => {});
  }

  private onWsMessage(raw: string): void {
    let m: Record<string, Object>;
    try {
      m = JSON.parse(raw) as Record<string, Object>;
    } catch (_) { return; }
    const t = (m['t'] as string) ?? '';
    if (t === 'player') {
      this.meJoined = !!(m['earthEnabled']);
    } else if (t === 'earth_snapshot') {
      this.handleEarthSnapshot(m);
    } else if (t === 'earth_revision') {
      const rev = m['revision'] as number;
      if (rev !== undefined && rev !== this.earthRevision) {
        this.earthRevision = rev;
        this.requestSnapshot();
      }
    }
  }

  private handleEarthSnapshot(m: Record<string, Object>): void {
    const rawNodes = m['nodes'];
    if (rawNodes === undefined || rawNodes === null) return;
    const arr = rawNodes as Array<Record<string, Object>>;
    const parsed: EarthNode[] = [];
    const meCode = this.identity !== undefined ? this.identity.code : '';
    for (let i = 0; i < arr.length; i++) {
      const node = EarthNode.fromRecord(arr[i]);
      if (meCode.length > 0 && node.code === meCode) {
        node.isMe = true;
      }
      parsed.push(node);
    }
    this.nodes = parsed;
    this.loadFailed = false;
    if (m['revision'] !== undefined) {
      this.earthRevision = m['revision'] as number;
    }
    console.info('[Earth] snapshot received, nodes: ' + parsed.length);
  }

  private requestSnapshot(): void {
    if (this.ws === undefined || this.wsState !== 1) return;
    this.requestSerial++;
    const requestID = this.uuid();
    const detail = earthDetailForDistance(this.cameraDistance);
    this.wsSend({
      't': 'earth_view',
      'requestID': requestID,
      'detail': detail,
      'bounds': []
    });
    if (this.snapshotTimerId >= 0) clearTimeout(this.snapshotTimerId);
    this.snapshotTimerId = setTimeout(() => {
      this.snapshotTimerId = -1;
      if (this.nodes.length === 0) {
        this.loadFailed = true;
      }
    }, 10000);
  }

  private joinEarth(): void {
    if (this.identity === undefined) return;
    const httpRequest = http.createHttp();
    const body = JSON.stringify({ 'enabled': true, 'cellID': 'v1:0:0' });
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.PUT,
      header: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + this.identity.token
      },
      expectDataType: http.HttpDataType.STRING,
      extraData: body,
      connectTimeout: 15000,
      readTimeout: 15000
    };
    httpRequest.request(API_BASE + '/api/players/me/earth', options).then((resp: http.HttpResponse) => {
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        this.meJoined = true;
        this.requestSnapshot();
      }
    }).catch((err: BusinessError) => {
      console.error('[Earth] joinEarth failed: ' + JSON.stringify(err));
    }).then(() => {
      httpRequest.destroy();
    });
  }

  private uuid(): string {
    const chars = '0123456789abcdef';
    let result = '';
    for (let i = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) {
        result += '-';
      } else if (i === 14) {
        result += '4';
      } else if (i === 19) {
        result += chars.charAt(Math.floor(Math.random() * 4) + 8);
      } else {
        result += chars.charAt(Math.floor(Math.random() * 16));
      }
    }
    return result;
  }
}
