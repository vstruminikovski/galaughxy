import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import './index.css';
import { useStudioStore } from './store/useStudioStore';

// Dev-only handle for debugging from the browser console.
if (import.meta.env.DEV) (window as unknown as { studio: typeof useStudioStore }).studio = useStudioStore;

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
