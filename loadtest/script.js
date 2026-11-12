// Профіль «мало записів, багато читань»: 1 POST + 9 GET на ітерацію.
// Фази: наростання 0→VUS, стале навантаження 5 хв, спад до 0 за 2 хв.
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:8000').replace(/\/$/, '');
const TOKEN = __ENV.TOKEN || '';
const VUS = parseInt(__ENV.VUS || '60', 10);
const THINK = parseFloat(__ENV.THINK || '0.3'); // пауза між запитами одного користувача, с
const LABEL = __ENV.LABEL || 'run';
const ASYNC = (__ENV.WRITE_MODE || 'sync') === 'async'; // async: POST /books/async → 202 → черга
const RAMP_UP = __ENV.RAMP_UP || '3m';
const STEADY = __ENV.STEADY || '5m';
const RAMP_DOWN = __ENV.RAMP_DOWN || '2m';

const AUTHORS = [
  'Taras Shevchenko', 'Lesya Ukrainka', 'Ivan Franko', 'Mykhailo Kotsiubynskyi', 'Olha Kobylianska',
  'Vasyl Stus', 'Lina Kostenko', 'Serhiy Zhadan', 'Yuri Andrukhovych', 'Oksana Zabuzhko',
];

const cacheHit = new Rate('cache_hit'); // частка X-Cache: HIT серед GET /books

export const options = {
  scenarios: {
    users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: RAMP_UP, target: VUS },
        { duration: STEADY, target: VUS },
        { duration: RAMP_DOWN, target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{op:list}': ['p(95)<1000'],
    'http_req_duration{op:create}': ['p(95)<2000'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const writeHeaders = {
  headers: { 'Content-Type': 'application/json', ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}) },
  tags: { op: 'create' },
};

function get(path, op) {
  const res = http.get(`${BASE_URL}${path}`, { tags: { op } });
  check(res, { [`${op} 200`]: (r) => r.status === 200 });
  sleep(THINK);
  return res;
}

function listBooks() {
  const res = get('/books?limit=50', 'list');
  const xc = res.headers['X-Cache'];
  if (xc === 'HIT' || xc === 'MISS') cacheHit.add(xc === 'HIT');
  return res;
}

export default function () {
  const author = AUTHORS[Math.floor(Math.random() * AUTHORS.length)];

  // 1 запис
  const created = http.post(
    `${BASE_URL}/books${ASYNC ? '/async' : ''}`,
    JSON.stringify({ title: `k6 vu${__VU} it${__ITER}`, author, year: 1800 + Math.floor(Math.random() * 225) }),
    writeHeaders,
  );
  let newId = null;
  let opId = null;
  if (ASYNC) {
    check(created, { 'create 202': (r) => r.status === 202 });
    opId = created.status === 202 ? created.json('operation_id') : null;
  } else {
    check(created, { 'create 201': (r) => r.status === 201 });
    newId = created.status === 201 ? created.json('id') : null;
  }
  sleep(THINK);

  // async: дізнатися результат операції; якщо вже done — отримати id створеної книги
  const pollOperation = () => {
    const op = get(`/operations/${opId}`, 'operation');
    try { if (op.json('status') === 'done') newId = op.json('book.id'); } catch (_) { /* ignore */ }
  };

  // 9 читань: список ×3, щойно створена книга ×2 (async: статус операції), випадкова книга ×2, автор ×2
  const list = listBooks();
  if (ASYNC && opId) pollOperation();
  else if (newId) get(`/books/${newId}`, 'get');
  get(`/authors/${encodeURIComponent(author)}`, 'author');
  listBooks();
  let books = [];
  try { books = list.json(); } catch (_) { /* помилка вже врахована в check */ }
  const pick = () => (books.length ? books[Math.floor(Math.random() * books.length)] : { id: newId || 1, author });
  get(`/books/${pick().id}`, 'get');
  get(`/authors/${encodeURIComponent(pick().author)}`, 'author');
  listBooks();
  if (newId) get(`/books/${newId}`, 'get');
  else if (opId) pollOperation();
  get(`/books/${pick().id}`, 'get');
}

function fmt(ms) { return ms === undefined ? '—' : `${ms.toFixed(1)} мс`; }

export function handleSummary(data) {
  const m = data.metrics;
  const d = m.http_req_duration.values;
  const rows = [
    ['Мітка прогону', LABEL],
    ['VUS / THINK / запис', `${VUS} / ${THINK} с / ${ASYNC ? 'async (202, черга)' : 'sync (201)'}`],
    ['Запитів усього', m.http_reqs.values.count],
    ['Запитів за секунду (середнє)', m.http_reqs.values.rate.toFixed(1)],
    ['Частка помилок', `${(m.http_req_failed.values.rate * 100).toFixed(2)} %`],
    ['Латентність p50', fmt(d.med)],
    ['Латентність p95', fmt(d['p(95)'])],
    ['Латентність p99', fmt(d['p(99)'])],
    ['Латентність max', fmt(d.max)],
  ];
  if (m['http_req_duration{op:list}']) rows.push(['p95 GET /books', fmt(m['http_req_duration{op:list}'].values['p(95)'])]);
  if (m['http_req_duration{op:create}']) rows.push([`p95 POST /books${ASYNC ? '/async' : ''}`, fmt(m['http_req_duration{op:create}'].values['p(95)'])]);
  if (m.cache_hit) rows.push(['Частка влучань у кеш (GET /books)', `${(m.cache_hit.values.rate * 100).toFixed(1)} %`]);

  const md = `| Показник | Значення |\n|---|---|\n${rows.map(([k, v]) => `| ${k} | ${v} |`).join('\n')}\n`;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }) + '\n\n' + md,
    [`results/${LABEL}-${stamp}.md`]: md,
    [`results/${LABEL}-${stamp}.json`]: JSON.stringify(data, null, 2),
  };
}
