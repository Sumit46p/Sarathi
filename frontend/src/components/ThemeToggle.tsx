import { Moon, Sun } from 'lucide-react';
import { useTheme } from '../hooks/useTheme';

const ThemeToggle = () => {
  const { isDark, toggleTheme } = useTheme();

  return (
    <button
      onClick={toggleTheme}
      className="btn-primary"
      style={{
        width: '40px',
        height: '40px',
        padding: '0',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'transparent',
        border: '1px solid var(--surface-border)',
        color: 'var(--text-main)',
      }}
      title="Toggle Dark Mode"
    >
      {isDark ? <Sun size={20} /> : <Moon size={20} />}
    </button>
  );
};

export default ThemeToggle;
