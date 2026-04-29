(function () {
  const CHART_JS_SCRIPT_ID = 'chartjs-cdn-loader';
  const CHART_JS_SRC = 'https://cdn.jsdelivr.net/npm/chart.js';

  function ensureChartJsLoaded() {
    return new Promise((resolve, reject) => {
      if (typeof window.Chart !== 'undefined') {
        resolve();
        return;
      }

      const existing = document.getElementById(CHART_JS_SCRIPT_ID);
      if (existing) {
        existing.addEventListener('load', () => resolve(), { once: true });
        existing.addEventListener('error', () => reject(new Error('Failed to load Chart.js')), {
          once: true,
        });
        return;
      }

      const script = document.createElement('script');
      script.id = CHART_JS_SCRIPT_ID;
      script.src = CHART_JS_SRC;
      script.defer = true;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error('Failed to load Chart.js'));
      document.head.appendChild(script);
    });
  }

  window.mustStartrackRenderChart = async function mustStartrackRenderChart(config) {
    const {
      canvasId,
      labels,
      values,
      title,
      colorHex,
    } = config || {};

    if (!canvasId) return;
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;

    try {
      await ensureChartJsLoaded();
    } catch (_) {
      return;
    }

    const existing = canvas._msChartInstance;
    if (existing) {
      existing.destroy();
    }

    const ctx = canvas.getContext('2d');
    if (!ctx || typeof window.Chart === 'undefined') return;

    const chart = new window.Chart(ctx, {
      type: 'bar',
      data: {
        labels: Array.isArray(labels) ? labels : [],
        datasets: [
          {
            label: title || 'Value',
            data: Array.isArray(values) ? values : [],
            borderWidth: 1,
            borderRadius: 6,
            backgroundColor: colorHex || '#1152D4',
            borderColor: colorHex || '#1152D4',
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: {
          duration: 550,
          easing: 'easeOutQuart',
        },
        plugins: {
          legend: { display: false },
        },
        scales: {
          x: {
            ticks: {
              maxRotation: 0,
              autoSkip: true,
              font: { size: 10 },
            },
          },
          y: {
            beginAtZero: true,
            ticks: {
              font: { size: 10 },
            },
          },
        },
      },
    });

    canvas._msChartInstance = chart;
  };
})();
