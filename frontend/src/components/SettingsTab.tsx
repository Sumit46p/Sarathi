import { useState, useEffect } from 'react';
import { Settings, User, Lock, Save, AlertCircle, CheckCircle2 } from 'lucide-react';
import { api } from '../api/auth';
import { toast } from './toast';

interface AdminProfile {
  id: number;
  username: string;
  email: string;
  organization_name: string;
}

export default function SettingsTab() {
  const [profile, setProfile] = useState<AdminProfile | null>(null);
  const [loading, setLoading] = useState(true);

  const [oldPassword, setOldPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  
  const [passwordLoading, setPasswordLoading] = useState(false);
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [passwordSuccess, setPasswordSuccess] = useState(false);

  useEffect(() => {
    let mounted = true;
    api.get('/auth/me/')
      .then(res => {
        if (mounted) setProfile(res.data);
      })
      .catch(err => console.error('Failed to fetch admin profile', err))
      .finally(() => {
        if (mounted) setLoading(false);
      });
    return () => { mounted = false; };
  }, []);

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError(null);
    setPasswordSuccess(false);

    if (newPassword !== confirmPassword) {
      setPasswordError("New passwords don't match.");
      return;
    }

    if (newPassword.length < 8) {
      setPasswordError("New password must be at least 8 characters long.");
      return;
    }

    setPasswordLoading(true);
    try {
      await api.post('/auth/change-password/', {
        old_password: oldPassword,
        new_password: newPassword,
      });
      setPasswordSuccess(true);
      setOldPassword('');
      setNewPassword('');
      setConfirmPassword('');
      toast.success('Password changed successfully');
    } catch (err: any) {
      console.error('Password change failed', err);
      setPasswordError(err.response?.data?.error || 'Failed to change password. Please check your current password.');
    } finally {
      setPasswordLoading(false);
    }
  };

  return (
    <section className="tab-content w-full" aria-labelledby="settings-heading">
      <div className="page-heading">
        <div>
          <h2 id="settings-heading">Workspace settings</h2>
          <p>Configuration and profile settings for your Sarthi operations workspace.</p>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 24, maxWidth: 640 }}>
        {/* Admin Profile Section */}
        <div className="card" style={{ padding: 24, border: '1px solid var(--surface-border)', borderRadius: 'var(--radius-lg)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20 }}>
            <div className="settings-icon" style={{ padding: 10, background: 'var(--primary-light)', color: 'var(--primary)', borderRadius: '50%' }}>
              <User size={20} />
            </div>
            <div>
              <h3 style={{ margin: 0, fontSize: '1.1rem' }}>Admin Profile</h3>
              <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '0.9rem' }}>Your workspace identity and organization</p>
            </div>
          </div>
          
          {loading ? (
            <div className="list-skeleton">
              <div className="skeleton-row" />
              <div className="skeleton-row" />
            </div>
          ) : profile ? (
            <div className="form-grid">
              <div className="form-group">
                <label>Username</label>
                <div className="input-field" style={{ backgroundColor: 'var(--surface-bg)', cursor: 'not-allowed', display: 'flex', alignItems: 'center' }}>
                  {profile.username}
                </div>
              </div>
              <div className="form-group">
                <label>Email Address</label>
                <div className="input-field" style={{ backgroundColor: 'var(--surface-bg)', cursor: 'not-allowed', display: 'flex', alignItems: 'center' }}>
                  {profile.email || '—'}
                </div>
              </div>
              <div className="form-group" style={{ gridColumn: '1 / -1' }}>
                <label>Organization Name</label>
                <div className="input-field" style={{ backgroundColor: 'var(--surface-bg)', cursor: 'not-allowed', display: 'flex', alignItems: 'center', fontWeight: 600 }}>
                  {profile.organization_name}
                </div>
                <p className="field-hint" style={{ marginTop: 6 }}>This determines which vehicles and drivers you can manage.</p>
              </div>
            </div>
          ) : (
            <div className="inline-alert error">
              <AlertCircle size={16} />
              Failed to load profile data.
            </div>
          )}
        </div>

        {/* Change Password Section */}
        <div className="card" style={{ padding: 24, border: '1px solid var(--surface-border)', borderRadius: 'var(--radius-lg)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20 }}>
            <div className="settings-icon" style={{ padding: 10, background: 'var(--primary-light)', color: 'var(--primary)', borderRadius: '50%' }}>
              <Lock size={20} />
            </div>
            <div>
              <h3 style={{ margin: 0, fontSize: '1.1rem' }}>Change Password</h3>
              <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '0.9rem' }}>Update your account security credentials</p>
            </div>
          </div>

          <form onSubmit={handleChangePassword}>
            <div className="form-grid" style={{ marginBottom: 20 }}>
              <div className="form-group" style={{ gridColumn: '1 / -1' }}>
                <label htmlFor="old-password">Current Password</label>
                <input 
                  id="old-password" 
                  type="password" 
                  className="input-field" 
                  placeholder="Enter your current password"
                  value={oldPassword}
                  onChange={e => setOldPassword(e.target.value)}
                  required
                />
              </div>
              
              <div className="form-group">
                <label htmlFor="new-password">New Password</label>
                <input 
                  id="new-password" 
                  type="password" 
                  className="input-field" 
                  placeholder="Min 8 characters"
                  value={newPassword}
                  onChange={e => setNewPassword(e.target.value)}
                  required
                  minLength={8}
                />
              </div>
              <div className="form-group">
                <label htmlFor="confirm-password">Confirm New Password</label>
                <input 
                  id="confirm-password" 
                  type="password" 
                  className="input-field" 
                  placeholder="Re-enter new password"
                  value={confirmPassword}
                  onChange={e => setConfirmPassword(e.target.value)}
                  required
                  minLength={8}
                />
              </div>
            </div>

            {passwordError && (
              <div className="inline-alert error" style={{ marginBottom: 16 }}>
                <AlertCircle size={16} />
                {passwordError}
              </div>
            )}

            {passwordSuccess && (
              <div className="inline-alert success" style={{ marginBottom: 16, backgroundColor: '#dcfce7', color: '#166534' }}>
                <CheckCircle2 size={16} />
                Password has been updated successfully.
              </div>
            )}

            <button 
              type="submit" 
              className="button button-primary" 
              disabled={passwordLoading || !oldPassword || !newPassword || !confirmPassword}
            >
              {passwordLoading ? 'Updating...' : 'Update Password'}
            </button>
          </form>
        </div>

      </div>
    </section>
  );
}
