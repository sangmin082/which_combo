// 릴레이 서버 통합 테스트: 방 생성 → 코드 입장 → 무브 릴레이 → 퇴장 알림
const { spawn } = require('child_process');
const WebSocket = require('ws');

const PORT = 8181;
const URL = `ws://127.0.0.1:${PORT}`;

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL);
    ws.inbox = [];
    ws.waiters = [];
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      const waiter = ws.waiters.shift();
      if (waiter) waiter(msg);
      else ws.inbox.push(msg);
    });
    ws.next = () =>
      new Promise((res, rej) => {
        if (ws.inbox.length) return res(ws.inbox.shift());
        ws.waiters.push(res);
        setTimeout(() => rej(new Error('메시지 수신 타임아웃')), 3000);
      });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

function assert(cond, label) {
  if (!cond) throw new Error(`실패: ${label}`);
  console.log(`  ✓ ${label}`);
}

async function main() {
  const server = spawn('node', ['index.js'], {
    cwd: __dirname,
    env: { ...process.env, PORT },
    stdio: 'inherit',
  });
  await new Promise((r) => setTimeout(r, 500));

  try {
    // 0) 개인정보 처리방침 페이지 (App Store 심사용)
    const privacyRes = await fetch(`http://127.0.0.1:${PORT}/privacy`);
    const privacyBody = await privacyRes.text();
    assert(privacyRes.status === 200 && privacyBody.includes('개인정보 처리방침'),
      '개인정보 처리방침 페이지 응답');

    // 1) 방 생성
    const host = await connect();
    host.send(JSON.stringify({ type: 'create' }));
    const roomMsg = await host.next();
    assert(roomMsg.type === 'room' && roomMsg.player === 0, '방 생성 응답');
    assert(/^[A-Z2-9]{6}$/.test(roomMsg.code), `방 코드 형식 (${roomMsg.code})`);

    // 2) 잘못된 코드 입장
    const stranger = await connect();
    stranger.send(JSON.stringify({ type: 'join', code: 'XXXXXX' }));
    const errMsg = await stranger.next();
    assert(errMsg.type === 'error', '존재하지 않는 방 코드 거부');
    stranger.close();

    // 3) 정상 입장 → 양쪽 start
    const guest = await connect();
    guest.send(JSON.stringify({ type: 'join', code: roomMsg.code }));
    const joinedMsg = await guest.next();
    assert(joinedMsg.type === 'joined' && joinedMsg.player === 1, '입장 응답');
    const startHost = await host.next();
    const startGuest = await guest.next();
    assert(startHost.type === 'start' && startGuest.type === 'start', '양쪽 start 수신');
    assert(startHost.first === startGuest.first, '선 플레이어 일치');
    assert([0, 1].includes(startHost.first), '선 플레이어 인덱스 유효');

    // 4) 무브 릴레이 (iOS 클라이언트와 동일한 인코딩)
    const move = { kind: 'place', cell: 12, value: 7 };
    host.send(JSON.stringify({ type: 'move', move }));
    const relayed = await guest.next();
    assert(relayed.type === 'move' && relayed.move.kind === 'place'
      && relayed.move.cell === 12 && relayed.move.value === 7,
      '무브 릴레이 (호스트→게스트)');

    const move2 = { kind: 'declare', line: 5 };
    guest.send(JSON.stringify({ type: 'move', move: move2 }));
    const relayed2 = await host.next();
    assert(relayed2.type === 'move' && relayed2.move.kind === 'declare' && relayed2.move.line === 5,
      '무브 릴레이 (게스트→호스트)');

    // 5) 퇴장 알림
    guest.close();
    const leftMsg = await host.next();
    assert(leftMsg.type === 'left', '상대 퇴장 알림');
    host.close();

    console.log('\n모든 테스트 통과 ✅');
  } finally {
    server.kill();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
