export class EarthNode {
  kind: string = '';
  code: string = '';
  latitude: number = 0;
  longitude: number = 0;
  score: number = 0;
  userCount: number = 0;
  totalWahs: number = 0;
  activeCount: number = 0;
  activeUntil: number = 0;
  isMe: boolean = false;
  cellID: string = '';

  static fromRecord(r: Record<string, Object>): EarthNode {
    const n = new EarthNode();
    n.kind = typeof r['kind'] === 'string' ? r['kind'] as string : '';
    n.code = typeof r['code'] === 'string' ? r['code'] as string : '';
    n.latitude = typeof r['latitude'] === 'number' ? r['latitude'] as number : 0;
    n.longitude = typeof r['longitude'] === 'number' ? r['longitude'] as number : 0;
    n.score = typeof r['score'] === 'number' ? r['score'] as number : 0;
    n.userCount = typeof r['userCount'] === 'number' ? r['userCount'] as number : 0;
    n.totalWahs = typeof r['totalWahs'] === 'number' ? r['totalWahs'] as number : 0;
    n.activeCount = typeof r['activeCount'] === 'number' ? r['activeCount'] as number : 0;
    n.activeUntil = typeof r['activeUntil'] === 'number' ? r['activeUntil'] as number : 0;
    n.isMe = r['isMe'] === true || r['isMe'] === 1;
    n.cellID = typeof r['cellID'] === 'string' ? r['cellID'] as string : '';
    return n;
  }
}

export class GeoPoint {
  x: number = 0;
  y: number = 0;
  z: number = 0;

  static create(x: number, y: number, z: number): GeoPoint {
    const p = new GeoPoint();
    p.x = x; p.y = y; p.z = z;
    return p;
  }
}

export class BoundarySegment {
  lat0: number = 0;
  lon0: number = 0;
  lat1: number = 0;
  lon1: number = 0;

  static create(lat0: number, lon0: number, lat1: number, lon1: number): BoundarySegment {
    const s = new BoundarySegment();
    s.lat0 = lat0; s.lon0 = lon0; s.lat1 = lat1; s.lon1 = lon1;
    return s;
  }
}

export class ProjectedLine {
  x1: number = 0;
  y1: number = 0;
  x2: number = 0;
  y2: number = 0;
  visible: boolean = false;
}

export class ProjectedDot {
  screenX: number = 0;
  screenY: number = 0;
  screenR: number = 0;
  isMe: boolean = false;
  node: EarthNode = new EarthNode();
}

export class RippleState {
  screenX: number = 0;
  screenY: number = 0;
  screenR: number = 6;
  phase: number = 0;

  static create(sx: number, sy: number, phase: number): RippleState {
    const r = new RippleState();
    r.screenX = sx; r.screenY = sy; r.phase = phase;
    return r;
  }
}

export function latLonToVec3(lat: number, lon: number, radius: number): GeoPoint {
  const phi = lat * Math.PI / 180;
  const theta = lon * Math.PI / 180;
  const r = Math.cos(phi);
  return GeoPoint.create(
    -r * Math.cos(theta) * radius,
    Math.sin(phi) * radius,
    r * Math.sin(theta) * radius
  );
}

export function earthDetailForDistance(d: number): number {
  if (d >= 3.75) return 0;
  if (d >= 3.35) return 1;
  if (d >= 2.70) return 2;
  if (d >= 2.10) return 3;
  return 4;
}
