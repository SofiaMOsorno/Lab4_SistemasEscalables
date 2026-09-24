import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    stages: [
        { duration: '30s', target: 10 },
    ],
    thresholds: {
        http_req_duration: ['p(95)<500'],
    },
};

export default function () {
    let response = http.get(__ENV.URL || 'http://cache-lab-alb-970937961.us-east-1.elb.amazonaws.com/');
    
    check(response, {
        'status is 200': (r) => r.status === 200,
        'response time < 100ms': (r) => r.timings.duration < 100,
        'response time < 500ms': (r) => r.timings.duration < 500,
    });

    sleep(0.1);
}