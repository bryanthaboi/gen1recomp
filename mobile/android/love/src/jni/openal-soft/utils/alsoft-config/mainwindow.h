#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <memory>

#include <QMainWindow>
#include <QListWidget>

namespace Ui {
class MainWindow;
}

class MainWindow : public QMainWindow {
    Q_OBJECT

private Q_SLOTS:
    void cancelCloseAction();

    void saveCurrentConfig();

    void saveConfigAsFile();
    void loadConfigFromFile();

    void showAboutPage();

    void enableApplyButton();

    void updateResamplerLabel(int num);

    void updatePeriodSizeEdit(int size);
    void updatePeriodSizeSlider();
    void updatePeriodCountEdit(int count);
    void updatePeriodCountSlider();

    void selectQuadDecoderFile();
    void select51DecoderFile();
    void select61DecoderFile();
    void select71DecoderFile();
    void select3D71DecoderFile();

    void updateJackBufferSizeEdit(int size);
    void updateJackBufferSizeSlider();

    void updateHrtfModeLabel(int num);
    void addHrtfFile();
    void removeHrtfFile();

    void updateHrtfRemoveButton();

    void showEnabledBackendMenu(QPoint pt);
    void showDisabledBackendMenu(QPoint pt);

    void selectOSSPlayback();
    void selectOSSCapture();

    void selectSolarisPlayback();

    void selectWaveOutput();

public:
    explicit MainWindow(QWidget *parent=nullptr);
    ~MainWindow() override;

private:
    std::unique_ptr<QValidator> mPeriodSizeValidator;
    std::unique_ptr<QValidator> mPeriodCountValidator;
    std::unique_ptr<QValidator> mSourceCountValidator;
    std::unique_ptr<QValidator> mEffectSlotValidator;
    std::unique_ptr<QValidator> mSourceSendValidator;
    std::unique_ptr<QValidator> mSampleRateValidator;
    std::unique_ptr<QValidator> mJackBufferValidator;

    std::unique_ptr<Ui::MainWindow> ui;

    bool mNeedsSave{};

    void closeEvent(QCloseEvent *event) override;

    void selectDecoderFile(QLineEdit *line, const char *caption);

    QStringList collectHrtfs();

    void loadConfig(const QString &fname);
    void saveConfig(const QString &fname) const;
};

#endif // MAINWINDOW_H
