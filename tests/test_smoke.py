"""冒烟测试与脚手架护栏。

这些用例不是在测业务逻辑。它们的作用有两个：

1. 保证 CI 管线从第一天起就是通的 —— 而不是等到第一次真提交才发现 CI 配错了；
2. 守住两条工程约束：模型权重不得入库、CI 不得引入 torch。

实现功能时请逐步补充真实用例（TC-xx），不要删掉这里的护栏。
"""

from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent


def test_ci_pipeline_runs():
    """CI 能装上依赖并执行到这一行，说明管线是通的。"""
    assert REPO_ROOT.is_dir()


def test_gitignore_excludes_model_weights_and_data():
    """权重与数据集不得入库。

    GitHub 免费 LFS 只有 1GB 存储 / 1GB·月流量，6 人克隆几轮就会耗尽，
    届时仓库会直接不可用。
    """
    gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
    for pattern in ("*.pt", "*.onnx", "data/*", "outputs/*", "~$*"):
        assert pattern in gitignore, f".gitignore 缺少规则：{pattern}"


def test_dependency_files_exist():
    for name in ("requirements.txt", "requirements-dev.txt"):
        assert (REPO_ROOT / name).is_file(), f"缺少依赖清单：{name}"


def test_dev_requirements_stay_free_of_runtime_deps():
    """CI 只安装 requirements-dev.txt。

    一旦它引入了运行时依赖，后处理就会悄悄依赖 torch，
    "纯 NumPy 实现因而可被 CI 单测"这条架构约束会随之失效 ——
    而这条约束正是我们证明"后处理是自主编写"的方式。
    """
    dev = (REPO_ROOT / "requirements-dev.txt").read_text(encoding="utf-8")
    for raw in dev.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        assert not line.startswith("-r "), (
            f"requirements-dev.txt 不应引用运行时依赖：{line}"
        )
        for forbidden in ("ultralytics", "torch", "opencv"):
            assert forbidden not in line, (
                f"requirements-dev.txt 不应包含 {forbidden}：{line}"
            )


def test_numpy_meets_postprocessing_requirement():
    """自研后处理（NMS / 阈值 / 类别过滤）建立在 NumPy 之上，版本需达标。"""
    major, minor = (int(x) for x in np.__version__.split(".")[:2])
    assert (major, minor) >= (1, 26), f"NumPy 版本过低：{np.__version__}"
