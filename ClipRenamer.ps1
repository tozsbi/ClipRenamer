# ClipRenamer app window. Run with: powershell -STA -ExecutionPolicy Bypass -File ClipRenamer.ps1
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

if (-not ('TozClipRow' -as [type])) {
    Add-Type -TypeDefinition @'
public class TozClipRow {
    public string Old { get; set; }
    public string New { get; set; }
    public string Path { get; set; }
}
'@
}

# Own taskbar identity, so the window groups with the pinned ClipRenamer shortcut instead of PowerShell
if (-not ('TozAppId' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class TozAppId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
}
[void][TozAppId]::SetCurrentProcessExplicitAppUserModelID('toz.ClipRenamer')

$Root = $PSScriptRoot
$SettingsFile = Join-Path $Root 'settings.json'
$LogFile = Join-Path $Root 'log.txt'
$TaskName = 'ClipRenamer - auto move'
$NamePattern = '^(Replay )?\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2}'
$VideoExt = '.mp4', '.mkv', '.mov', '.flv'

function Get-Settings {
    $s = [ordered]@{
        Source       = "$env:USERPROFILE\Videos"
        Dest         = "$env:USERPROFILE\iCloudDrive\Clips"
        RenameFolder = "$env:USERPROFILE\iCloudDrive\Clips"
        NamedFolder  = "$env:USERPROFILE\iCloudDrive\Named Clips"
        GraceHours   = 24
        ApiKey       = ''
        AutoName     = $false
        Provider     = 'local'
        LocalModel   = 'qwen3-vl:8b-instruct'
        NameLanguage = 'English'
        UiLanguage   = 'English'
    }
    if (Test-Path -LiteralPath $SettingsFile) {
        $saved = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($s.Keys)) { if ($saved.$k) { $s[$k] = $saved.$k } }
    }
    $s
}
function Save-Settings($s) { $s | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8 }
$Settings = Get-Settings
$Arabic = $Settings.UiLanguage -eq 'Arabic'
function L([string]$en, [string]$ar) { if ($Arabic) { $ar } else { $en } }

$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ClipRenamer" Width="1180" Height="720" MinWidth="980" MinHeight="600"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="CanResize"
        Background="#120809" FlowDirection="LeftToRight" FontFamily="Segoe UI" Foreground="#E6E8EB">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="0" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <SolidColorBrush x:Key="Accent" Color="#A3121F"/>
    <SolidColorBrush x:Key="Muted" Color="#9E8B8E"/>
    <SolidColorBrush x:Key="Panel" Color="#1E0F11"/>
    <SolidColorBrush x:Key="Line" Color="#3A1B1F"/>

    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="MinWidth" Value="8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border Background="#4A2429" CornerRadius="4" Margin="1,0"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#B3A3A5"/>
      <Setter Property="FontSize" Value="17"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,26,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Grid Background="Transparent">
              <ContentPresenter VerticalAlignment="Center"/>
              <Border x:Name="Bar" Height="3" VerticalAlignment="Bottom" Background="#A3121F" Visibility="Hidden" CornerRadius="2"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter Property="Foreground" Value="White"/>
                <Setter TargetName="Bar" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="White"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="#3A1B1F"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BlueBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#A3121F"/>
    </Style>
    <Style x:Key="Chrome" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#B3A3A5"/>
      <Setter Property="Padding" Value="14,4"/>
      <Setter Property="FontSize" Value="13"/>
    </Style>

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#1E0F11"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Padding" Value="22"/>
      <Setter Property="Margin" Value="0,0,0,14"/>
    </Style>
    <Style x:Key="H" TargetType="TextBlock">
      <Setter Property="FontSize" Value="22"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#9E8B8E"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Path" TargetType="TextBlock">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Foreground" Value="#E6E8EB"/>
      <Setter Property="FlowDirection" Value="LeftToRight"/>
      <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="76"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="300"/>
    </Grid.ColumnDefinitions>

    <!-- Top bar -->
    <Grid x:Name="TopBar" Grid.Row="0" Grid.Column="0" Background="#120809" Margin="28,0,12,0">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Border Width="40" Height="40" CornerRadius="20" Background="#A3121F" Margin="0,0,14,0">
          <TextBlock Text="C" FontSize="22" FontWeight="Black" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-4,0,0"/>
        </Border>
        <TextBlock Text="ClipRenamer" FontSize="20" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,40,0" FlowDirection="LeftToRight"/>
        <RadioButton x:Name="NavHome" Style="{StaticResource Nav}" Content="Home" IsChecked="True" Height="76"/>
        <RadioButton x:Name="NavMove" Style="{StaticResource Nav}" Content="Move" Height="76"/>
        <RadioButton x:Name="NavRename" Style="{StaticResource Nav}" Content="Rename" Height="76"/>
      </StackPanel>
    </Grid>

    <!-- Sidebar header + window buttons -->
    <Grid Grid.Row="0" Grid.Column="1" Background="#170B0D">
      <StackPanel Orientation="Horizontal" VerticalAlignment="Top" HorizontalAlignment="Right">
        <Button x:Name="BtnLang" Style="{StaticResource Chrome}" ToolTip="English / عربي"/>
        <Button x:Name="BtnMin" Style="{StaticResource Chrome}" Content="—"/>
        <Button x:Name="BtnClose" Style="{StaticResource Chrome}" Content="✕"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Bottom" Margin="20,0,20,12">
        <Border Width="38" Height="38" CornerRadius="19" Background="#3A1B1F" Margin="0,0,10,0">
          <TextBlock x:Name="UserInitials" FontSize="12" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" FlowDirection="LeftToRight"/>
        </Border>
        <StackPanel VerticalAlignment="Center">
          <TextBlock x:Name="UserName" FontSize="15" FontWeight="SemiBold" Foreground="#FF6B6B"/>
          <TextBlock x:Name="SideStatus" Text="..." FontSize="12" Foreground="#9E8B8E"/>
        </StackPanel>
      </StackPanel>
    </Grid>

    <!-- Main content -->
    <Grid Grid.Row="1" Grid.Column="0" Margin="28,8,24,24">

      <!-- HOME -->
      <Grid x:Name="PageHome">
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" CornerRadius="8" Padding="40">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#4A0E16" Offset="0"/>
              <GradientStop Color="#2A0A0F" Offset="0.6"/>
              <GradientStop Color="#140809" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
          <Grid>
            <StackPanel VerticalAlignment="Center">
              <TextBlock Text="Your clips, sorted for you" FontSize="34" FontWeight="Bold" Foreground="White"/>
              <TextBlock Text="Moves your OBS clips to the folder you choose, so you can give them your own names." FontSize="16" Foreground="#D8C8CA" Margin="0,8,0,30" TextWrapping="Wrap"/>
              <WrapPanel>
                <Border Background="#33000000" CornerRadius="6" Padding="20,14" Margin="0,0,14,0">
                  <StackPanel>
                    <TextBlock x:Name="CountWaiting" Text="0" FontSize="30" FontWeight="Bold" Foreground="White"/>
                    <TextBlock Text="clips waiting to move" Foreground="#C9B5B8" FontSize="13"/>
                  </StackPanel>
                </Border>
                <Border Background="#33000000" CornerRadius="6" Padding="20,14" Margin="0,0,14,0">
                  <StackPanel>
                    <TextBlock x:Name="CountDest" Text="0" FontSize="30" FontWeight="Bold" Foreground="White"/>
                    <TextBlock Text="clips in the save folder" Foreground="#C9B5B8" FontSize="13"/>
                  </StackPanel>
                </Border>
                <Border Background="#33000000" CornerRadius="6" Padding="20,14">
                  <StackPanel>
                    <TextBlock x:Name="StatusBig" Text="Off" FontSize="30" FontWeight="Bold" Foreground="White"/>
                    <TextBlock Text="Auto move" Foreground="#C9B5B8" FontSize="13"/>
                  </StackPanel>
                </Border>
              </WrapPanel>
            </StackPanel>
          </Grid>
        </Border>
        <Grid Grid.Row="1" Margin="0,18,0,0">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
            <Button x:Name="BtnPlay" Style="{StaticResource BlueBtn}" Width="270" Height="58" FontSize="22" FontWeight="Bold" Content="Start"/>
            <Button x:Name="BtnGear" Style="{StaticResource BlueBtn}" Width="58" Height="58" FontSize="20" Margin="2,0,0,0" Content="⚙" ToolTip="Choose folders"/>
          </StackPanel>
          <TextBlock x:Name="HomeHint" Style="{StaticResource Sub}" VerticalAlignment="Center" HorizontalAlignment="Right" FontSize="13"/>
        </Grid>
      </Grid>

      <!-- MOVE -->
      <ScrollViewer x:Name="PageMove" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <TextBlock Style="{StaticResource H}" Text="Move"/>
          <TextBlock Style="{StaticResource Sub}" Text="Choose where clips come from and where they go." Margin="0,0,0,18"/>
          <Border Style="{StaticResource Card}">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="From (your OBS folder)" FontWeight="SemiBold" FontSize="15" Margin="0,0,0,6"/>
                <TextBlock x:Name="TxtSource" Style="{StaticResource Path}" HorizontalAlignment="Left"/>
              </StackPanel>
              <Button x:Name="BtnPickSource" Grid.Column="1" Style="{StaticResource Btn}" Content="Change" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <Border Style="{StaticResource Card}">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="To (for example iCloud Drive)" FontWeight="SemiBold" FontSize="15" Margin="0,0,0,6"/>
                <TextBlock x:Name="TxtDest" Style="{StaticResource Path}" HorizontalAlignment="Left"/>
              </StackPanel>
              <Button x:Name="BtnPickDest" Grid.Column="1" Style="{StaticResource Btn}" Content="Change" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <Border Style="{StaticResource Card}">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="Where named clips go" FontWeight="SemiBold" FontSize="15" Margin="0,0,0,6"/>
                <TextBlock x:Name="TxtNamed" Style="{StaticResource Path}" HorizontalAlignment="Left"/>
              </StackPanel>
              <Button x:Name="BtnOpenNamed" Grid.Column="1" Style="{StaticResource Btn}" Content="Open" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <Button x:Name="BtnPickNamed" Grid.Column="2" Style="{StaticResource Btn}" Content="Change" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="If you don't name a clip" FontWeight="SemiBold" FontSize="15" Margin="0,0,0,8"/>
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Sub}" Text="After" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <TextBox x:Name="GraceBox" Width="60" Background="#120809" Foreground="White" BorderBrush="#4A2429" Padding="6,5" FontSize="14" CaretBrush="White" HorizontalContentAlignment="Center" FlowDirection="LeftToRight"/>
                <TextBlock Style="{StaticResource Sub}" Text="hours it gets its date as name (like 2026-10-23 00-20-09) and moves to the named clips folder." VerticalAlignment="Center" Margin="8,0,0,0"/>
              </StackPanel>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="How it works" FontWeight="SemiBold" FontSize="15" Margin="0,0,0,6"/>
              <TextBlock Style="{StaticResource Sub}" Text="• Only moves OBS clips (named by date, like Replay 2026-09-07 14-57-40)."/>
              <TextBlock Style="{StaticResource Sub}" Text="• Never overwrites a file. If the name is taken it adds a number like (2)."/>
              <TextBlock Style="{StaticResource Sub}" Text="• Never touches a clip OBS is still recording."/>
              <TextBlock Style="{StaticResource Sub}" Text="• Once started, it runs once every 24 hours, even when the app is closed."/>
            </StackPanel>
          </Border>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="BtnMoveNow" Style="{StaticResource BlueBtn}" Content="Move now" Margin="0,0,10,0"/>
            <Button x:Name="BtnOpenDest" Style="{StaticResource Btn}" Content="Open save folder"/>
          </StackPanel>
        </StackPanel>
      </ScrollViewer>

      <!-- RENAME -->
      <Grid x:Name="PageRename" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0">
          <TextBlock Style="{StaticResource H}" Text="Rename"/>
          <TextBlock Style="{StaticResource Sub}" Text="Pick a folder and edit the new name of each clip. Nothing changes until you press Apply names." Margin="0,0,0,14"/>
        </StackPanel>
        <Border Grid.Row="1" Style="{StaticResource Card}" Padding="18,14">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock Text="Folder" FontWeight="SemiBold" FontSize="15" Margin="0,0,0,4"/>
              <TextBlock x:Name="TxtRenameFolder" Style="{StaticResource Path}" HorizontalAlignment="Left"/>
            </StackPanel>
            <Button x:Name="BtnPickRename" Grid.Column="1" Style="{StaticResource Btn}" Content="Change" VerticalAlignment="Center"/>
          </Grid>
        </Border>
        <Border Grid.Row="2" Background="#1E0F11" CornerRadius="6">
          <Grid>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <ItemsControl x:Name="ClipList" Margin="12">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Border BorderBrush="#3A1B1F" BorderThickness="0,0,0,1" Padding="6,10">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="Auto"/>
                          <ColumnDefinition Width="260"/>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Uid="play" Style="{StaticResource Btn}" Content="▶" Tag="{Binding Path}" Padding="12,6" Margin="0,0,12,0" ToolTip="Play clip"/>
                        <Button Grid.Column="3" Uid="delete" Style="{StaticResource Btn}" Content="🗑" Tag="{Binding Path}" Padding="12,6" Margin="12,0,0,0" ToolTip="Delete clip"/>
                        <TextBlock Grid.Column="1" Text="{Binding Old}" Foreground="#9E8B8E" FontSize="13" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding Old}" Margin="0,0,12,0"/>
                        <TextBox Grid.Column="2" Text="{Binding New, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" Background="#120809" Foreground="White" BorderBrush="#4A2429" Padding="8,6" FontSize="14" CaretBrush="White" VerticalContentAlignment="Center"/>
                      </Grid>
                    </Border>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </ScrollViewer>
            <TextBlock x:Name="EmptyList" Text="No clips in this folder." Style="{StaticResource Sub}" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
          </Grid>
        </Border>
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,14,0,0">
          <Button x:Name="BtnApply" Style="{StaticResource BlueBtn}" Content="Apply names" Margin="0,0,10,0"/>
          <Button x:Name="BtnReload" Style="{StaticResource Btn}" Content="Refresh list" Margin="0,0,14,0"/>
        </StackPanel>
      </Grid>
    </Grid>

    <!-- Sidebar: recent activity -->
    <Grid Grid.Row="1" Grid.Column="1" Background="#170B0D">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <TextBlock Text="▾  Recent activity" FontSize="14" Foreground="#D8C8CA" Margin="20,16,20,10"/>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <ItemsControl x:Name="ActivityList" Margin="12,0,12,12">
          <ItemsControl.ItemTemplate>
            <DataTemplate>
              <Grid Margin="8,6">
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Border Width="34" Height="34" CornerRadius="17" Background="{Binding Color}" Margin="0,0,10,0" VerticalAlignment="Top">
                  <TextBlock Text="{Binding Icon}" Foreground="White" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="{Binding Title}" Foreground="#FF6B6B" FontSize="13" TextTrimming="CharacterEllipsis" ToolTip="{Binding Title}"/>
                  <TextBlock Text="{Binding When}" Foreground="#9E8B8E" FontSize="12"/>
                </StackPanel>
              </Grid>
            </DataTemplate>
          </ItemsControl.ItemTemplate>
        </ItemsControl>
      </ScrollViewer>
    </Grid>
  </Grid>
</Window>
'@

# Arabic version of the window: same layout, Arabic text, right-to-left
$XamlArabic = [ordered]@{
    'Content="Home"' = 'Content="الرئيسية"'
    'Content="Move" Height' = 'Content="النقل" Height'
    'Content="Rename" Height' = 'Content="التسمية" Height'
    'Content="AI" Height' = 'Content="الذكاء الاصطناعي" Height'
    'Text="Your clips, sorted for you"' = 'Text="مقاطعك مرتّبة لحالها"'
    'Text="Moves your OBS clips to the folder you choose, so you can give them your own names."' = 'Text="ينقل مقاطع OBS للمجلد اللي تختاره، وتسمّيها أنت باللي تبيه."'
    'Text="clips waiting to move"' = 'Text="مقطع ينتظر النقل"'
    'Text="clips in the save folder"' = 'Text="مقطع في مجلد الحفظ"'
    'Text="Off" FontSize' = 'Text="موقف" FontSize'
    'Text="Auto move" Foreground' = 'Text="النقل التلقائي" Foreground'
    'Content="Start"/>' = 'Content="تشغيل"/>'
    'ToolTip="Choose folders"' = 'ToolTip="اختيار المجلدات"'
    'Text="Move"/>' = 'Text="النقل"/>'
    'Text="Choose where clips come from and where they go."' = 'Text="اختر من وين ياخذ المقاطع، ووين يحطها."'
    'Text="From (your OBS folder)"' = 'Text="من وين؟ (مجلد OBS)"'
    'Text="To (for example iCloud Drive)"' = 'Text="إلى وين؟ (مثلاً iCloud)"'
    'Text="Where named clips go"' = 'Text="المقاطع اللي تسمّت، وين تروح؟"'
    'Text="If you don''t name a clip"' = 'Text="إذا ما سمّيت المقطع"'
    'Text="After"' = 'Text="بعد"'
    'Text="hours it gets its date as name (like 2026-10-23 00-20-09) and moves to the named clips folder."' = 'Text="ساعة، يتسمّى بتاريخه (مثل 2026-10-23 00-20-09) وينتقل لمجلد المقاطع المسمّاة."'
    'Content="Open"' = 'Content="فتح"'
    'Content="Change"' = 'Content="تغيير"'
    'Text="How it works"' = 'Text="كيف يشتغل؟"'
    'Text="• Only moves OBS clips (named by date, like Replay 2026-09-07 14-57-40)."' = 'Text="• ينقل بس مقاطع OBS (اللي اسمها تاريخ، مثل Replay 2026-09-07 14-57-40)."'
    'Text="• Never overwrites a file. If the name is taken it adds a number like (2)."' = 'Text="• ما يكتب فوق أي ملف. إذا الاسم موجود يضيف رقم مثل (2)."'
    'Text="• Never touches a clip OBS is still recording."' = 'Text="• ما يلمس المقطع اللي OBS لسا يسجّله."'
    'Text="• Once started, it runs once every 24 hours, even when the app is closed."' = 'Text="• إذا شغّلته، يشتغل لحاله مرة كل 24 ساعة، حتى لو البرنامج مقفل."'
    'Content="Move now"' = 'Content="انقل الحين"'
    'Content="Open save folder"' = 'Content="افتح مجلد الحفظ"'
    'Text="AI"/>' = 'Text="الذكاء الاصطناعي"/>'
    'Text="The app looks at frames from the clip and listens to the voice chat, then the AI names it after what happened."' = 'Text="البرنامج يشوف صور المقطع ويسمع الفويس، وبعدها Claude يعطيه اسم على اللي صار فيه."'
    'Text="⚠ Tools missing"' = 'Text="⚠ الأدوات ناقصة"'
    'Text="The app needs tools to read video and listen to audio (about 1.8 GB, one time only)."' = 'Text="البرنامج يحتاج أدوات تقرأ الفيديو وتسمع الصوت (تقريباً 1.8 جيجا، مرة وحدة بس)."'
    'Content="Download tools"' = 'Content="نزّل الأدوات"'
    'Text="Who names your clips?"' = 'Text="مين يسمّي المقاطع؟"'
    'Text="Free AI on your PC (Ollama)"' = 'Text="ذكاء اصطناعي مجاني على جهازك (Ollama)"'
    'Text="Free, and everything stays on your PC. Names are simpler."' = 'Text="مجاني، وكل شي يصير على جهازك وما يطلع شي للإنترنت. الأسماء أبسط شوي."'
    'Text="Claude (more accurate, needs credit)"' = 'Text="Claude (أدق، بس يحتاج رصيد)"'
    'Text="Smarter names, understands jokes and slang better. Roughly one or two cents per clip."' = 'Text="أسماء أذكى ويفهم اللهجة والنكت أكثر. تقريباً 5 هللات لكل مقطع."'
    'Text="Claude API key"' = 'Text="مفتاح Claude"'
    'Text="Create an Anthropic account, add credit, then copy your key and paste it here. It is stored encrypted, on your PC only."' = 'Text="تسوي حساب في موقع Anthropic، وتشحن فيه رصيد، وتنسخ المفتاح وتلصقه هنا. ينحفظ مشفّر على جهازك بس."'
    'Content="Save"' = 'Content="حفظ"'
    'Content="Get a key"' = 'Content="جيب مفتاح"'
    'Text="Name new clips automatically after they move"' = 'Text="سمّ المقاطع الجديدة تلقائياً بعد ما تنتقل"'
    'Text="Every new clip the app moves gets named on its own. Auto move needs to be on."' = 'Text="كل مقطع جديد ينقله البرنامج، يسمّيه لحاله بدون ما تسوي شي. يحتاج النقل التلقائي يكون شغّال."'
    'Text="• Takes 6 frames from the clip and turns the voice chat into text on your PC."' = 'Text="• ياخذ 6 صور من المقطع، ويحوّل كلام الفويس لكتابة على جهازك."'
    'Text="• The AI then looks at the frames and the text and picks a name."' = 'Text="• بعدها الذكاء الاصطناعي يشوف الصور والكلام ويعطي اسم."'
    'Text="• With Claude only: the frames and the text are sent online. The audio itself never leaves your PC."' = 'Text="• مع Claude بس: الصور والكلام المكتوب يطلعون للإنترنت. الصوت نفسه ما يطلع أبداً."'
    'Text="• Naming one clip takes about 30 seconds to a minute."' = 'Text="• تسمية المقطع الواحد تاخذ تقريباً نص دقيقة إلى دقيقة."'
    'Text="Rename"/>' = 'Text="التسمية"/>'
    'Text="Pick a folder and edit the new name of each clip. Nothing changes until you press Apply names."' = 'Text="اختر المجلد، وعدّل الاسم الجديد لكل مقطع. ما يتغيّر شي إلا لما تضغط «طبّق الأسماء»."'
    'Text="Folder"' = 'Text="المجلد"'
    'ToolTip="Play clip"' = 'ToolTip="شغّل المقطع"'
    'ToolTip="Delete clip"' = 'ToolTip="احذف المقطع (يروح لسلة المحذوفات)"'
    'Text="No clips in this folder."' = 'Text="ما فيه مقاطع في هذا المجلد."'
    'Content="✨ Suggest names with AI"' = 'Content="✨ اقترح أسماء بالذكاء الاصطناعي"'
    'Content="Apply names"' = 'Content="طبّق الأسماء"'
    'Content="Refresh list"' = 'Content="تحديث القائمة"'
    'Text="▾  Recent activity"' = 'Text="▾  آخر النشاط"'
    'Background="#120809" FlowDirection="LeftToRight"' = 'Background="#120809" FlowDirection="RightToLeft"'
    '<StackPanel Orientation="Horizontal" VerticalAlignment="Top" HorizontalAlignment="Right">' = '<StackPanel Orientation="Horizontal" VerticalAlignment="Top" HorizontalAlignment="Left" FlowDirection="LeftToRight">'
    'Style="{StaticResource Path}" HorizontalAlignment="Left"' = 'Style="{StaticResource Path}" HorizontalAlignment="Right"'
    'Text="Clip name language"' = 'Text="لغة أسماء المقاطع"'
    '<TextBlock Text="English" Margin="8,0,0,0"/>' = '<TextBlock Text="إنجليزي" Margin="8,0,0,0"/>'
    'Text="Arabic (Saudi dialect)"' = 'Text="عربي (لهجة سعودية)"'
}
if ($Arabic) { foreach ($k in $XamlArabic.Keys) { $xamlText = $xamlText.Replace($k, $XamlArabic[$k]) } }
[xml]$xaml = $xamlText

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$IconFile = Join-Path $Root 'ClipRenamer.ico'
if (Test-Path -LiteralPath $IconFile) { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$IconFile) }
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    if ($n) { $ui[$n] = $win.FindName($n) }
}

function Pick-Folder($current, $title) {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = $title
    $d.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $current) { $d.SelectedPath = $current }
    if ($d.ShowDialog() -eq 'OK') { return $d.SelectedPath }
    $null
}

function Get-ObsClips($folder) {
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object {
        $VideoExt -contains $_.Extension.ToLower() -and $_.BaseName -match $NamePattern })
}

function Test-AutoOn { [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) }

function Format-Ago([datetime]$t) {
    $d = (Get-Date) - $t
    if ($d.TotalMinutes -lt 1) { L 'just now' 'الحين' }
    elseif ($d.TotalHours -lt 1) { (L "$([int]$d.TotalMinutes) min ago" "قبل $([int]$d.TotalMinutes) دقيقة") }
    elseif ($d.TotalDays -lt 1) { (L "$([int]$d.TotalHours) h ago" "قبل $([int]$d.TotalHours) ساعة") }
    else { (L "$([int]$d.TotalDays) d ago" "قبل $([int]$d.TotalDays) يوم") }
}

function Refresh-Activity {
    $items = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $LogFile) {
        $lines = Get-Content -LiteralPath $LogFile -Tail 40 -Encoding UTF8
        [array]::Reverse($lines)
        foreach ($l in $lines) {
            if ($l -notmatch '^(\S+ \S+)\s+(.*)$') { continue }
            $when = Format-Ago ([datetime]$Matches[1]); $msg = $Matches[2]
            if ($msg -match '^AI') { continue }  # old lines from the removed AI naming
            if ($msg -match '^Moved: (.+?) -> ') { $o = @{ Icon = '⇪'; Color = '#A3121F'; Title = (L "Moved: $($Matches[1])" "انتقل: $($Matches[1])") } }
            elseif ($msg -match '^Renamed: .+? -> (.+)$') { $o = @{ Icon = '✎'; Color = '#6B1520'; Title = (L "Named: $($Matches[1])" "تسمّى: $($Matches[1])") } }
            elseif ($msg -match '^Dated: .+? -> (.+)$') { $o = @{ Icon = '📅'; Color = '#4A2429'; Title = (L "Named by date: $($Matches[1])" "تسمّى بتاريخه: $($Matches[1])") } }
            elseif ($msg -match '^Deleted \(.+?\): (.+)$') { $o = @{ Icon = '🗑'; Color = '#4A2429'; Title = (L "Deleted: $($Matches[1])" "انحذف: $($Matches[1])") } }
            elseif ($msg -match '^Skipped \(in use\): (.+)$') { $o = @{ Icon = '●'; Color = '#E0A030'; Title = (L "Waiting (still recording): $($Matches[1])" "ينتظر (يتسجّل): $($Matches[1])") } }
            else { $o = @{ Icon = '!'; Color = '#D9534F'; Title = $msg } }
            $o.When = $when
            [void]$items.Add([pscustomobject]$o)
        }
    }
    if ($items.Count -eq 0) { [void]$items.Add([pscustomobject]@{ Icon = '·'; Color = '#3A1B1F'; Title = (L 'No activity yet' 'ما فيه نشاط للحين'); When = '' }) }
    $ui.ActivityList.ItemsSource = $items
}

function Refresh-Status {
    $on = Test-AutoOn
    $ui.StatusBig.Text = if ($on) { L 'On' 'شغّال' } else { L 'Off' 'موقف' }
    $ui.SideStatus.Text = if ($on) { L 'Auto move is on' 'النقل التلقائي شغّال' } else { L 'Auto move is off' 'النقل التلقائي موقف' }
    $ui.BtnPlay.Content = if ($on) { L 'Stop' 'إيقاف' } else { L 'Start' 'تشغيل' }
    $ui.BtnPlay.Background = if ($on) { [Windows.Media.BrushConverter]::new().ConvertFrom('#4A2429') } else { [Windows.Media.BrushConverter]::new().ConvertFrom('#A3121F') }
    $ui.CountWaiting.Text = (Get-ObsClips $Settings.Source).Count
    $ui.CountDest.Text = if (Test-Path -LiteralPath $Settings.Dest) { @(Get-ChildItem -LiteralPath $Settings.Dest -File -ErrorAction SilentlyContinue | Where-Object { $VideoExt -contains $_.Extension.ToLower() }).Count } else { 0 }
    $ui.HomeHint.Text = (L "From: $($Settings.Source)`nTo: $($Settings.Dest)" "من: $($Settings.Source)`nإلى: $($Settings.Dest)")
    $ui.TxtSource.Text = $Settings.Source
    $ui.TxtDest.Text = $Settings.Dest
    $ui.TxtRenameFolder.Text = $Settings.RenameFolder
    $ui.TxtNamed.Text = $Settings.NamedFolder
    Refresh-Activity
}

function Load-RenameList {
    $folder = $Settings.RenameFolder
    $rows = New-Object System.Collections.ObjectModel.ObservableCollection[TozClipRow]
    if (Test-Path -LiteralPath $folder) {
        Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
            Where-Object { $VideoExt -contains $_.Extension.ToLower() } | Sort-Object Name | ForEach-Object {
                $r = New-Object TozClipRow
                $r.Old = $_.Name; $r.Path = $_.FullName
                $r.New = $_.Name
                $rows.Add($r)
            }
    }
    $ui.ClipList.ItemsSource = $rows
    $ui.EmptyList.Visibility = if ($rows.Count) { 'Collapsed' } else { 'Visible' }
}

function Write-Log($msg) {
    Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8
}

function Show-Page($name) {
    foreach ($p in 'PageHome', 'PageMove', 'PageRename') { $ui[$p].Visibility = 'Collapsed' }
    $ui[$name].Visibility = 'Visible'
    if ($name -eq 'PageRename') { Load-RenameList }
}

$ui.UserName.Text = $env:USERNAME
$ui.UserInitials.Text = $env:USERNAME.Substring(0, [Math]::Min(3, $env:USERNAME.Length))

# --- Events ---
$ui.TopBar.Add_MouseLeftButtonDown({ $win.DragMove() })
$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })

# Language switch: save the choice and reopen the window in the other language
$ui.BtnLang.Content = L '🌐 عربي' '🌐 English'
$ui.BtnLang.Add_Click({
    $Settings.UiLanguage = if ($Arabic) { 'English' } else { 'Arabic' }
    Save-Settings $Settings
    Start-Process wscript.exe -ArgumentList "`"$(Join-Path $Root 'ClipRenamer.vbs')`""
    $win.Close()
})
$ui.BtnClose.Add_Click({ $win.Close() })
$ui.NavHome.Add_Checked({ Show-Page 'PageHome' })
$ui.NavMove.Add_Checked({ Show-Page 'PageMove' })
$ui.NavRename.Add_Checked({ Show-Page 'PageRename' })

$ui.BtnGear.Add_Click({ $ui.NavMove.IsChecked = $true })

$ui.BtnPlay.Add_Click({
    if (Test-AutoOn) {
        & (Join-Path $Root 'Uninstall.ps1') | Out-Null
    } else {
        Save-Settings $Settings
        & (Join-Path $Root 'Install.ps1') | Out-Null
    }
    Refresh-Status
})

$ui.BtnPickSource.Add_Click({
    $p = Pick-Folder $Settings.Source (L 'Choose the folder where OBS saves clips' 'اختر المجلد اللي يحفظ فيه OBS المقاطع')
    if ($p) { $Settings.Source = $p; Save-Settings $Settings; Refresh-Status }
})
$ui.BtnPickDest.Add_Click({
    $p = Pick-Folder $Settings.Dest (L 'Choose the folder clips should move to' 'اختر المجلد اللي تبي المقاطع تنتقل له')
    if ($p) { $Settings.Dest = $p; Save-Settings $Settings; Refresh-Status }
})
$ui.BtnPickNamed.Add_Click({
    $p = Pick-Folder $Settings.NamedFolder (L 'Choose the folder named clips go to' 'اختر المجلد اللي تروح له المقاطع بعد ما تتسمّى')
    if ($p) { $Settings.NamedFolder = $p; Save-Settings $Settings; Refresh-Status }
})
$ui.BtnOpenNamed.Add_Click({
    if (-not (Test-Path -LiteralPath $Settings.NamedFolder)) { New-Item -ItemType Directory -Path $Settings.NamedFolder -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList "`"$($Settings.NamedFolder)`""
})
$ui.GraceBox.Text = [string]$Settings.GraceHours
$ui.GraceBox.Add_LostFocus({
    $h = 0
    if ([double]::TryParse($ui.GraceBox.Text, [ref]$h) -and $h -ge 0) { $Settings.GraceHours = $h; Save-Settings $Settings }
    else { $ui.GraceBox.Text = [string]$Settings.GraceHours }
})
$ui.BtnPickRename.Add_Click({
    $p = Pick-Folder $Settings.RenameFolder (L 'Choose the folder with clips to rename' 'اختر المجلد اللي تبي تسمّي مقاطعه')
    if ($p) { $Settings.RenameFolder = $p; Save-Settings $Settings; Refresh-Status; Load-RenameList }
})

$ui.BtnMoveNow.Add_Click({
    Save-Settings $Settings
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $Root 'Move-Clips.ps1')`""
})
$ui.BtnOpenDest.Add_Click({ if (Test-Path -LiteralPath $Settings.Dest) { Start-Process explorer.exe -ArgumentList "`"$($Settings.Dest)`"" } })
$ui.BtnReload.Add_Click({ Load-RenameList })

# Play and delete buttons inside the clip list
Add-Type -AssemblyName Microsoft.VisualBasic
$ui.ClipList.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($s, $e)
    $btn = $e.OriginalSource
    $path = $btn.Tag
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
    if ($btn.Uid -eq 'play') { Start-Process -FilePath $path; return }
    if ($btn.Uid -eq 'delete') {
        $name = Split-Path $path -Leaf
        $inICloud = $path -like "$env:USERPROFILE\iCloudDrive\*"
        $where = if ($inICloud) { (L 'It goes to Recently Deleted in iCloud (icloud.com), where you can restore it for 30 days.' 'بيروح لـ «المحذوفات مؤخراً» في iCloud (موقع icloud.com)، ويبقى هناك 30 يوم تقدر ترجّعه فيها.') } else { (L 'It goes to the Recycle Bin, where you can restore it.' 'بيروح لسلة المحذوفات، وتقدر ترجّعه منها.') }
        $answer = [Windows.MessageBox]::Show($win, (L "Delete this clip?`n`n$name`n`n$where" "تبي تحذف هذا المقطع؟`n`n$name`n`n$where"), 'ClipRenamer', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        try {
            if ($inICloud) {
                # iCloud refuses the Windows Recycle Bin (error 0x8007017B); it keeps deleted files in Recently Deleted instead
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                Write-Log "Deleted (iCloud recently deleted): $name"
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
                Write-Log "Deleted (recycle bin): $name"
            }
        } catch { Write-Log "FAILED delete: ${name}: $($_.Exception.Message)" }
        Load-RenameList; Refresh-Activity
    }
})

$ui.BtnApply.Add_Click({
    $bad = [IO.Path]::GetInvalidFileNameChars()
    $done = 0; $skipped = 0
    foreach ($r in @($ui.ClipList.ItemsSource)) {
        $new = $r.New.Trim()
        if (-not $new -or $new -eq $r.Old) { continue }
        if ($new.IndexOfAny($bad) -ge 0) { $skipped++; Write-Log "Bad name (skipped): $new"; continue }
        if ([IO.Path]::GetExtension($new) -eq '') { $new += [IO.Path]::GetExtension($r.Old) }
        # Named clips go to their own folder so they don't mix with the unnamed ones
        if (-not (Test-Path -LiteralPath $Settings.NamedFolder)) { New-Item -ItemType Directory -Path $Settings.NamedFolder -Force | Out-Null }
        $target = Join-Path $Settings.NamedFolder $new
        if (Test-Path -LiteralPath $target) { $skipped++; Write-Log "Name taken (skipped): $new"; continue }
        try { Move-Item -LiteralPath $r.Path -Destination $target -ErrorAction Stop; $done++; Write-Log "Renamed: $($r.Old) -> $new" }
        catch { $skipped++; Write-Log "FAILED: $($r.Old): $($_.Exception.Message)" }
    }
    Load-RenameList; Refresh-Activity
    $msg = (L "Renamed $done clips and moved them to the ""$(Split-Path $Settings.NamedFolder -Leaf)"" folder." "تغيّر اسم $done مقطع، وانتقلوا لمجلد «$(Split-Path $Settings.NamedFolder -Leaf)».")
    if ($skipped) { $msg += (L "`nSkipped $skipped (name taken or has characters Windows does not allow)." "`nوتخطّيت $skipped (الاسم موجود أو فيه رموز ممنوعة).") }
    [Windows.MessageBox]::Show($win, $msg, 'ClipRenamer') | Out-Null
})

# Keep numbers and activity fresh
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({ Refresh-Status })
$timer.Start()

Refresh-Status
[void]$win.ShowDialog()