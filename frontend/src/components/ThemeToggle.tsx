import { Moon, Sun } from 'lucide-react';
import { useTheme } from '../hooks/useTheme';

const ThemeToggle = () => {
  const { isDark, toggleTheme } = useTheme();

  return (
    <button
      onClick={toggleTheme}
      className="icon-button theme-toggle"
      title={isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
      aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
    >
      <Sun size={16} className={`theme-icon ${!isDark ? 'active' : ''}`} />
      <Moon size={16} className={`theme-icon ${isDark ? 'active' : ''}`} />
    </button>
  );
};

export default ThemeToggle;
