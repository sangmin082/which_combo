// 위치, 콤보! — 2인용 온라인 대전 릴레이 서버
//
// 프로토콜 (JSON over WebSocket)
//   클라이언트 → 서버
//     {"type":"create"}                 방 생성
//     {"type":"join","code":"ABC123"}   방 입장
//     {"type":"move","move":{...}}      무브 릴레이 (서버는 내용을 해석하지 않음)
//   서버 → 클라이언트
//     {"type":"room","code":"ABC123","player":0}   방 생성 완료 (방장 = 0)
//     {"type":"joined","player":1}                 입장 완료 (참가자 = 1)
//     {"type":"start","first":0|1}                 대국 시작, first = 선 플레이어 인덱스
//     {"type":"move","move":{...}}                 상대의 무브
//     {"type":"left"}                              상대 퇴장
//     {"type":"error","message":"..."}             오류

const fs = require('fs');
const http = require('http');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const PRIVACY_HTML = fs.readFileSync(path.join(__dirname, 'privacy.html'), 'utf8');
// 헷갈리기 쉬운 문자(0/O, 1/I)를 뺀 코드 알파벳
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;

/** code → { sockets: [creator, joiner|null], started: boolean } */
const rooms = new Map();

function generateCode() {
  let code;
  do {
    code = Array.from({ length: CODE_LENGTH }, () =>
      CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)]
    ).join('');
  } while (rooms.has(code));
  return code;
}

function send(ws, message) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(message));
}

function opponentOf(room, ws) {
  return room.sockets[0] === ws ? room.sockets[1] : room.sockets[0];
}

// 클라우드(Render 등) 헬스체크용 HTTP 서버 위에 WebSocket을 얹는다
const httpServer = http.createServer((req, res) => {
  // App Store 심사용 개인정보 처리방침 페이지
  if (req.url === '/privacy' || req.url === '/privacy/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(PRIVACY_HTML);
    return;
  }
  if (req.url === '/robots.txt') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('User-agent: *\nAllow: /\n');
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('위치, 콤보! 릴레이 서버 동작 중\n');
});
const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
  ws.roomCode = null;
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      return send(ws, { type: 'error', message: '잘못된 메시지 형식입니다.' });
    }

    switch (msg.type) {
      case 'create': {
        if (ws.roomCode) return send(ws, { type: 'error', message: '이미 방에 있습니다.' });
        const code = generateCode();
        rooms.set(code, { sockets: [ws, null], started: false });
        ws.roomCode = code;
        send(ws, { type: 'room', code, player: 0 });
        break;
      }

      case 'join': {
        if (ws.roomCode) return send(ws, { type: 'error', message: '이미 방에 있습니다.' });
        const code = String(msg.code || '').toUpperCase().trim();
        const room = rooms.get(code);
        if (!room) return send(ws, { type: 'error', message: '존재하지 않는 방 코드입니다.' });
        if (room.sockets[1]) return send(ws, { type: 'error', message: '방이 가득 찼습니다.' });
        room.sockets[1] = ws;
        room.started = true;
        ws.roomCode = code;
        send(ws, { type: 'joined', player: 1 });
        // 선(先)은 랜덤 배정
        const first = Math.random() < 0.5 ? 0 : 1;
        room.sockets.forEach((s) => send(s, { type: 'start', first }));
        break;
      }

      case 'move': {
        const room = rooms.get(ws.roomCode);
        if (!room || !room.started) {
          return send(ws, { type: 'error', message: '대국이 시작되지 않았습니다.' });
        }
        send(opponentOf(room, ws), { type: 'move', move: msg.move });
        break;
      }

      default:
        send(ws, { type: 'error', message: `알 수 없는 메시지: ${msg.type}` });
    }
  });

  ws.on('close', () => {
    const room = rooms.get(ws.roomCode);
    if (!room) return;
    send(opponentOf(room, ws), { type: 'left' });
    rooms.delete(ws.roomCode);
  });
});

// 30초마다 ping — 응답 없는(끊긴) 연결을 정리해 상대에게 퇴장을 빨리 알린다
setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

httpServer.listen(PORT, () => {
  console.log(`위치, 콤보! 릴레이 서버 실행 중 — ws://0.0.0.0:${PORT}`);
});
