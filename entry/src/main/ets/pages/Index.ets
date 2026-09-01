import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { sensor } from '@kit.SensorServiceKit';
import { webSocket, http } from '@kit.NetworkKit';
import { geoLocationManager } from '@kit.LocationKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';

const WS_URL = 'wss://zhuzhiliao.aimfor.top/api/ws';

class NativeBridge {
  private ws: webSocket.WebSocket | null = null;
  // 鸿蒙 webSocket.WebSocket 不公开 readyState，自行维护：0=连接中 1=已连接 3=已关闭
  private wsState: number = 3;
  private controller: webview.WebviewController | null = null;
  private onEarthStateChange: ((open: boolean) => void) | null = null;

  setController(c: webview.WebviewController) {
    this.controller = c;
  }

  setOnEarthStateChange(cb: (open: boolean) => void) {
    this.onEarthStateChange = cb;
  }

  /** Web → Native: 通知地球视图打开/关闭状态 */
  notifyEarthState(open: boolean): void {
    if (this.onEarthStateChange) {
      this.onEarthStateChange(open);
    }
  }

  /** Web → Native: 打开原生地球页面 */
  openNativeEarth(): void {
    router.pushUrl({ url: 'pages/EarthPage' }).catch((err: BusinessError) => {
      console.error('pushUrl EarthPage failed: ' + JSON.stringify(err));
    });
  }

  /** Web → Native: 带 Authorization 头连接 WebSocket */
  wsConnect(token: string): void {
    this.closeWs();
    try {
      this.ws = webSocket.createWebSocket();
      this.wsState = 0;
      this.ws.on('open', () => {
        this.wsState = 1;
        this.runJS('window.__bridge && __bridge.onWsOpen && __bridge.onWsOpen()');
      });
      this.ws.on('message', (err, data) => {
        const msg = typeof data === 'string' ? data : String(data);
        this.runJS(`window.__bridge && __bridge.onWsMessage && __bridge.onWsMessage(${JSON.stringify(msg)})`);
      });
      this.ws.on('close', () => {
        this.wsState = 3;
        this.runJS('window.__bridge && __bridge.onWsClose && __bridge.onWsClose()');
      });
      this.ws.on('error', () => {
        this.wsState = 3;
        this.runJS('window.__bridge && __bridge.onWsClose && __bridge.onWsClose()');
      });

      const header: Record<string, string> = { 'Authorization': `Bearer ${token}` };
      this.ws.connect(WS_URL, { header })
        .then(() => {})
        .catch((err: Error) => {
          this.wsState = 3;
          console.error('WS connect failed: ' + err.message);
          this.runJS('window.__bridge && __bridge.onWsClose && __bridge.onWsClose()');
        });
    } catch (err) {
      this.wsState = 3;
      console.error('wsConnect error: ' + JSON.stringify(err));
      this.runJS('window.__bridge && __bridge.onWsClose && __bridge.onWsClose()');
    }
  }

  /** Web → Native: 发送 WebSocket 消息 */
  wsSend(message: string): void {
    if (this.ws && this.wsState === 1) {
      this.ws.send(message).catch(() => {});
    }
  }

  /** Web → Native: 关闭 WebSocket */
  wsClose(): void {
    this.closeWs();
  }

  /** Web → Native: 请求设备位置（粗略） */
  requestLocation(): void {
    try {
      const request: geoLocationManager.LocationRequest = {
        'priority': geoLocationManager.LocationRequestPriority.LOW_POWER,
        'scenario': geoLocationManager.LocationRequestScenario.UNSET,
        'maxAccuracy': 5000
      };
      console.info('[Location] getCurrentLocation start');
      geoLocationManager.getCurrentLocation(request)
        .then((location: geoLocationManager.Location) => {
          console.info('[Location] ok: ' + location.latitude + ',' + location.longitude);
          // 与 index.html 中注册的回调名一致：__bridge.onLocation / __bridge.onLocationError
          this.runJS(`window.__bridge && __bridge.onLocation && __bridge.onLocation({latitude:${location.latitude},longitude:${location.longitude}})`);
        })
        .catch((err: BusinessError) => {
          console.error('[Location] failed: ' + JSON.stringify(err));
          this.runJS(`window.__bridge && __bridge.onLocationError && __bridge.onLocationError(${JSON.stringify(err.message || '定位失败')})`);
        });
    } catch (err) {
      console.error('[Location] error: ' + JSON.stringify(err));
      this.runJS(`window.__bridge && __bridge.onLocationError && __bridge.onLocationError('定位服务不可用')`);
    }
  }

  /** Web → Native: 发起 HTTP 请求，绕过 ArkWeb 的 CORS 限制
   *  seq: 调用方生成的唯一序号，用于回调配对
   *  method: GET/POST/PUT/DELETE
   *  url: 完整 URL
   *  authToken: Authorization 头的 token 值（不含 "Bearer " 前缀），可为空
   *  body: 请求体字符串（POST/PUT 使用），可为空
   */
  httpFetch(seq: number, method: string, url: string, authToken: string, body: string): void {
    const httpRequest = http.createHttp();
    const headerObj: Record<string, string> = {};
    if (authToken) {
      headerObj['Authorization'] = `Bearer ${authToken}`;
    }
    if (method === 'POST' || method === 'PUT') {
      headerObj['Content-Type'] = 'application/json';
    }

    // 根据 method 字符串映射到 RequestMethod 枚举
    let httpMethod: http.RequestMethod = http.RequestMethod.GET;
    if (method === 'POST') {
      httpMethod = http.RequestMethod.POST;
    } else if (method === 'PUT') {
      httpMethod = http.RequestMethod.PUT;
    } else if (method === 'DELETE') {
      httpMethod = http.RequestMethod.DELETE;
    }

    const options: http.HttpRequestOptions = {
      method: httpMethod,
      header: headerObj,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 15000
    };
    if (body && (method === 'POST' || method === 'PUT')) {
      options.extraData = body;
    }

    httpRequest.request(url, options)
      .then((resp: http.HttpResponse) => {
        const result = JSON.stringify({
          seq,
          status: resp.responseCode,
          body: typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result)
        });
        this.runJS(`window.__bridge && __bridge.onHttpResult && __bridge.onHttpResult(${JSON.stringify(result)})`);
      })
      .catch((err: BusinessError) => {
        const result = JSON.stringify({
          seq,
          status: 0,
          body: err.message || '网络请求失败'
        });
        this.runJS(`window.__bridge && __bridge.onHttpResult && __bridge.onHttpResult(${JSON.stringify(result)})`);
      })
      .then(() => {
        httpRequest.destroy();
      });
  }

  private closeWs() {
    if (this.ws) {
      try {
        this.ws.off('open');
        this.ws.off('message');
        this.ws.off('close');
        this.ws.off('error');
        if (this.wsState === 1) {
          this.ws.close({ code: 1001, reason: 'going away' });
        }
      } catch (_) {}
      this.ws = null;
    }
    this.wsState = 3;
  }

  private runJS(script: string) {
    if (this.controller) {
      this.controller.runJavaScript(script).catch(() => {});
    }
  }
}

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  private bridge: NativeBridge = new NativeBridge();
  @State earthViewOpen: boolean = false;
  private lastTouchX: number = 0;
  private lastTouchY: number = 0;
  private touchTracking: boolean = false;
  private lastPinchDist: number = 0;
  private pinchTracking: boolean = false;

  aboutToAppear() {
    webview.WebviewController.setWebDebuggingAccess(true);
    this.bridge.setController(this.controller);
    this.bridge.setOnEarthStateChange((open: boolean) => {
      this.earthViewOpen = open;
    });
  }

  aboutToDisappear() {
    try { sensor.off(sensor.SensorId.ACCELEROMETER); } catch (_) {}
    this.bridge.wsClose();
  }

  build() {
    Column() {
      Web({ src: $rawfile('index.html'), controller: this.controller })
        .domStorageAccess(true)
        .databaseAccess(true)
        .javaScriptAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        .geolocationAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .width('100%')
        .height('100%')
        .onPageBegin(() => {
        })
        .onPageEnd(() => {
          this.startAccelInjection();
          this.injectThreeJS();
          this.injectGeoJSON();
          this.injectEarthOverride();
        })
        .onControllerAttached(() => {
          try {
            this.controller.setCustomUserAgent(this.controller.getUserAgent() + ' ZhuzhiliaoHarmony/1.0');
          } catch (err) {
            console.error('setUserAgent failed: ' + JSON.stringify(err));
          }
          // 桥接必须在页面脚本执行前注册，避免页面初始化时 __nativeBridge 缺失导致竞态
          this.registerBridge();
        })
        // ArkWeb OSR 模式下 TouchMove 被内置 PanRecognizer 拦截且不转发给网页，
        // parallelGesture 也被 Web 组件内置手势抢占。改用 onTouch 原始事件回调，
        // 在手势识别之前捕获 TouchMove，通过 runJavaScript 直接更新地球旋转。
        .onTouch((event: TouchEvent) => {
          if (!this.earthViewOpen) return;
          if (event.touches.length === 2) {
            this.touchTracking = false;
            const x1 = event.touches[0].x, y1 = event.touches[0].y;
            const x2 = event.touches[1].x, y2 = event.touches[1].y;
            const dist = Math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2));
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              if (this.pinchTracking && this.lastPinchDist > 0) {
                const ratio = dist / this.lastPinchDist;
                this.lastPinchDist = dist;
                this.controller.runJavaScript(
                  `try{window.__arkPinchMove && window.__arkPinchMove(${ratio.toFixed(4)})}catch(e){}`
                ).catch(() => {});
              } else {
                this.lastPinchDist = dist;
                this.pinchTracking = true;
              }
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pinchTracking = false;
              this.lastPinchDist = 0;
            }
            return;
          }
          if (event.touches.length !== 1) {
            this.touchTracking = false;
            this.pinchTracking = false;
            return;
          }
          this.pinchTracking = false;
          const tx = event.touches[0].x;
          const ty = event.touches[0].y;
          if (event.type === TouchType.Down) {
            this.lastTouchX = tx;
            this.lastTouchY = ty;
            this.touchTracking = true;
          } else if (event.type === TouchType.Move && this.touchTracking) {
            const dx = tx - this.lastTouchX;
            const dy = ty - this.lastTouchY;
            this.lastTouchX = tx;
            this.lastTouchY = ty;
            if (Math.abs(dx) > 0.1 || Math.abs(dy) > 0.1) {
              this.controller.runJavaScript(
                `try{window.__arkPanMove && window.__arkPanMove(${dx.toFixed(2)},${dy.toFixed(2)})}catch(e){}`
              ).catch(() => {});
            }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.touchTracking = false;
          }
        })
    }
    .width('100%')
    .height('100%')
  }

  private startAccelInjection() {
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data) => {
        const script = `try{window.__harmonyAccel={x:${data.x.toFixed(4)},y:${data.y.toFixed(4)},z:${data.z.toFixed(4)},t:performance.now()}}catch(_){}`;
        this.controller.runJavaScript(script).catch(() => {});
      }, { interval: 25 });
      console.info('Accel injection started');
    } catch (err) {
      console.error('Accel injection failed: ' + JSON.stringify(err));
    }
  }

  private registerBridge() {
    try {
      this.controller.registerJavaScriptProxy(
        this.bridge,
        '__nativeBridge',
        ['wsConnect', 'wsSend', 'wsClose', 'requestLocation', 'httpFetch', 'notifyEarthState', 'openNativeEarth']
      );
      console.info('Native bridge registered');
    } catch (err) {
      console.error('registerBridge failed: ' + JSON.stringify(err));
    }
  }

  private injectEarthOverride() {
    const script = `try{
      var _eb=document.getElementById('earthBtn');
      if(_eb){
        var _clone=_eb.cloneNode(true);
        _eb.parentNode.replaceChild(_clone,_eb);
        _clone.addEventListener('click',function(e){
          e.stopPropagation();
          e.preventDefault();
          if(window.__nativeBridge){ window.__nativeBridge.openNativeEarth(); }
        });
      }
    }catch(_){}`;
    this.controller.runJavaScript(script).catch(() => {});
  }

  /** 读取 rawfile 中的 three.earth.min.js 并注入到页面，绕过 ArkWeb 不支持 <script src> 的限制 */
  private injectThreeJS() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const rm = context.resourceManager;
      rm.getRawFileContent('3d/vendor/three.earth.min.js').then((content: Uint8Array) => {
        const textDecoder = util.TextDecoder.create('utf-8');
        const code = textDecoder.decodeToString(content);
        // 用 IIFE 包裹：three.earth.min.js 内部用 const 声明了大量单字母变量（W/H 等），
        // 直接在全局作用域执行会与 index.html 中的同名全局变量冲突（SyntaxError: Identifier 'W' has already been declared），
        // 导致脚本中断、window.THREE_EARTH 无法挂载。IIFE 隔离作用域后，内部变量不污染全局，但 window.THREE_EARTH 赋值仍生效。
        const wrapped = '(function(){\n' + code + '\n})();';
        this.controller.runJavaScript(wrapped).then(() => {
          console.info('Three.js injected (IIFE wrapped), size: ' + code.length);
        }).catch((err: BusinessError) => {
          console.error('Three.js injection failed: ' + JSON.stringify(err));
        });
      }).catch((err: BusinessError) => {
        console.error('readRawFile three.earth.min.js failed: ' + JSON.stringify(err));
      });
    } catch (err) {
      console.error('injectThreeJS error: ' + JSON.stringify(err));
    }
  }

  /** 读取 rawfile 中的国家边界 GeoJSON 并注入到页面，用于绘制地图轮廓 */
  private injectGeoJSON() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const rm = context.resourceManager;
      rm.getRawFileContent('3d/vendor/ne_110m_admin_0_countries.geojson').then((content: Uint8Array) => {
        const textDecoder = util.TextDecoder.create('utf-8');
        const jsonStr = textDecoder.decodeToString(content);
        // GeoJSON 本身就是合法 JSON，直接注入为 JS 对象
        this.controller.runJavaScript('window.__geoJSON = ' + jsonStr + ';').then(() => {
          console.info('GeoJSON injected, size: ' + jsonStr.length);
        }).catch((err: BusinessError) => {
          console.error('GeoJSON injection failed: ' + JSON.stringify(err));
        });
      }).catch((err: BusinessError) => {
        console.error('readRawFile GeoJSON failed: ' + JSON.stringify(err));
      });
    } catch (err) {
      console.error('injectGeoJSON error: ' + JSON.stringify(err));
    }
  }
}
